import Foundation
import Combine

/// Drives the 15-minute polling loop. For each watched task it checks for
/// completion (removing + notifying) and for new comments (alerting Slack).
@MainActor
final class Poller: ObservableObject {
    static let interval: TimeInterval = 15 * 60

    /// Set when a comment alert fires; the menu bar uses it to show a badge.
    @Published var hasUnseenActivity = false

    /// When the last full poll pass completed. Surfaced in the popover.
    @Published var lastCheckedAt: Date?

    /// True while a poll is in flight, so the UI can show progress.
    @Published var isChecking = false

    static let shared = Poller(store: .shared)

    private unowned let store: AppStore
    private var timer: Timer?

    init(store: AppStore) {
        self.store = store
    }

    func start() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        self.timer = timer
        // Run one poll shortly after launch so the user isn't waiting 15 minutes.
        Task { @MainActor in await poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clearActivityBadge() {
        hasUnseenActivity = false
    }

    /// Run a single polling pass over all watched tasks.
    func poll() async {
        // Guards against overlapping passes (timer firing during a manual check).
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        // Skip silently if credentials aren't configured yet.
        guard store.hasCredentials, let api = store.makeAPIClient() else {
            NSLog("[TaskWatch] Skipping poll — credentials missing")
            return
        }

        // Resolve who "I" am once, if we'll need it to filter own comments.
        let ignoredAuthorId = await resolveIgnoredAuthorId(api: api)

        // Resolve the Slack DM target once. If unavailable we still poll (to
        // advance baselines / handle completion) but can't send alerts.
        let slack = store.makeSlackAPI()
        let channelId = await resolveSlackChannel(slack: slack)

        // Snapshot the list; mutations happen back through the store by id.
        let tasks = store.tasks

        for task in tasks {
            await pollTask(task, api: api, slack: slack, channelId: channelId, ignoredAuthorId: ignoredAuthorId)
        }

        lastCheckedAt = Date()
    }

    /// Resolve the Slack member id to DM (from the configured email), cached.
    /// Returns nil if Slack isn't configured or lookup fails.
    private func resolveSlackChannel(slack: SlackAPI?) async -> String? {
        guard let slack else { return nil }
        if let cached = store.slackMemberId { return cached }

        let email = store.notifyEmail.trimmed
        guard !email.isEmpty else { return nil }
        do {
            let id = try await slack.lookupUserId(email: email)
            store.setSlackMemberId(id)
            return id
        } catch {
            NSLog("[TaskWatch] Couldn't resolve Slack user for \(email): \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns the author id whose comments should be suppressed, or nil when the
    /// feature is off or the identity can't be resolved (fail open → still alert).
    private func resolveIgnoredAuthorId(api: TeamworkAPI) async -> String? {
        guard store.ignoreOwnComments else { return nil }
        if let cached = store.currentUserId { return cached }
        do {
            let id = try await api.fetchCurrentUserId()
            store.setCurrentUserId(id)
            return id
        } catch {
            NSLog("[TaskWatch] Couldn't resolve current user via /me.json: \(error.localizedDescription)")
            return nil
        }
    }

    private func pollTask(_ task: WatchedTask, api: TeamworkAPI, slack: SlackAPI?, channelId: String?, ignoredAuthorId: String?) async {
        var task = task

        // 1. Completion check (also backfills task name / project name).
        do {
            let item = try await api.fetchTask(taskId: task.taskId)
            if item.status?.lowercased() == "completed" {
                let name = item.content ?? task.taskName
                store.removeTask(taskId: task.taskId)
                Notifier.taskCompleted(taskName: name)
                return // No point checking comments on a removed task.
            }
            store.updateMetadata(taskId: task.taskId, taskName: item.content, projectName: item.projectName)
            // Reflect the refreshed metadata in the copy used for this pass's alert.
            if let project = item.projectName, !project.isEmpty { task.projectName = project }
            if let name = item.content, !name.isEmpty { task.taskName = name }
        } catch {
            NSLog("[TaskWatch] Failed to fetch task \(task.taskId): \(error.localizedDescription)")
            // Fall through — a status fetch failure shouldn't block comment checks.
        }

        // 2. New comment check.
        do {
            let comments = try await api.fetchComments(taskId: task.taskId)

            let baseline = task.lastSeenCommentId?.asCommentInt ?? -1
            let newComments = comments.filter { $0.id.asCommentInt > baseline }
            guard let newestNew = newComments.newest else { return }

            // Alert on the newest comment that isn't ours (when filtering is on).
            let alertable = newComments.filter { comment in
                guard let ignoredAuthorId else { return true }
                return comment.authorId != ignoredAuthorId
            }

            if alertable.isEmpty {
                NSLog("[TaskWatch] Task \(task.taskId): \(newComments.count) new comment(s) suppressed by ignore-own-comments")
            }

            if let toAlert = alertable.newest {
                // Something to alert: if Slack can't deliver, leave the baseline
                // untouched so we retry once Slack is configured correctly,
                // rather than silently swallowing the comment.
                guard let slack, let channelId else {
                    NSLog("[TaskWatch] New comment on \(task.taskId) but no Slack DM target; will retry")
                    return
                }
                await SlackNotifier.notifyNewComment(slack: slack, channelId: channelId, task: task, comment: toAlert)
                hasUnseenActivity = true
            }

            // Advance the baseline past every new comment — including our own —
            // so suppressed comments aren't reconsidered next poll.
            store.updateLastSeen(taskId: task.taskId, commentId: newestNew.id)
        } catch {
            NSLog("[TaskWatch] Failed to fetch comments for \(task.taskId): \(error.localizedDescription)")
        }
    }
}
