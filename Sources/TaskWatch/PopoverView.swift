import SwiftUI
import AppKit

/// The menu bar popover: watched-task list, an add field, and footer actions.
struct PopoverView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var poller: Poller

    @State private var urlInput = ""
    @State private var errorMessage: String?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.tasks.isEmpty {
                Text("No tasks watched yet.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                taskList
            }

            Divider()
            checkNowRow
            Divider()
            addSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { poller.clearActivityBadge() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Watched Tasks")
                .font(.headline)
            Spacer()
            Text("\(store.tasks.count)/\(AppStore.maxWatchedTasks)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var taskList: some View {
        VStack(spacing: 4) {
            ForEach(store.tasks) { task in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.taskName)
                            .lineLimit(2)
                            .font(.callout)
                        if let project = task.projectName, !project.isEmpty {
                            Text(project)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let url = URL(string: task.taskUrl) {
                            Link("Open in Teamwork", destination: url)
                                .font(.caption2)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.removeTask(taskId: task.taskId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from watch list")
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private var checkNowRow: some View {
        HStack {
            Button {
                Task { await poller.poll() }
            } label: {
                if poller.isChecking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                } else {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
            }
            .disabled(poller.isChecking || store.tasks.isEmpty)

            Spacer()

            if let lastChecked = poller.lastCheckedAt {
                Text("Checked \(lastChecked, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste Teamwork task URL")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("https://yourco.teamwork.com/tasks/12345", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Watch") { add() }
                    .disabled(isAdding || urlInput.trimmed.isEmpty || store.isAtCapacity)
            }
            if isAdding {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Adding…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.isAtCapacity {
                Text("Watch list is full (max \(AppStore.maxWatchedTasks)).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Preferences…") { PreferencesWindowController.show() }
                .buttonStyle(.link)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.callout)
    }

    // MARK: - Add flow

    private func add() {
        errorMessage = nil

        guard let taskId = TeamworkAPI.parseTaskId(from: urlInput) else {
            errorMessage = TeamworkError.invalidURL.errorDescription
            return
        }
        guard !store.contains(taskId: taskId) else {
            errorMessage = "You're already watching that task."
            return
        }
        guard !store.isAtCapacity else {
            errorMessage = "Watch list is full (max \(AppStore.maxWatchedTasks))."
            return
        }
        guard store.hasCredentials, let api = store.makeAPIClient() else {
            errorMessage = "Add your Teamwork and Slack details in Preferences first."
            PreferencesWindowController.show()
            return
        }

        let taskUrl = urlInput.trimmed
        isAdding = true

        Task {
            defer { isAdding = false }
            do {
                let item = try await api.fetchTask(taskId: taskId)
                let comments = try await api.fetchComments(taskId: taskId)
                let baseline = comments.newest?.id

                let task = WatchedTask(
                    taskId: taskId,
                    taskName: item.content ?? "Task \(taskId)",
                    taskUrl: taskUrl,
                    lastSeenCommentId: baseline
                )
                store.addTask(task)
                urlInput = ""
                errorMessage = nil
            } catch let error as TeamworkError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
