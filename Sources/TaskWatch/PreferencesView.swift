import SwiftUI

/// Credentials window. Secrets (Teamwork token, Slack bot token) go to the
/// Keychain; site URL + notify email go to UserDefaults.
struct PreferencesView: View {
    @EnvironmentObject private var store: AppStore

    @State private var token = ""
    @State private var siteURL = ""
    @State private var slackBotToken = ""
    @State private var notifyEmail = ""
    @State private var savedConfirmation = false

    @State private var isTesting = false
    /// Result of the last "Send test DM": (success, message).
    @State private var testResult: (ok: Bool, message: String)?

    private var canSave: Bool {
        !token.trimmed.isEmpty
            && !siteURL.trimmed.isEmpty
            && !slackBotToken.trimmed.isEmpty
            && !notifyEmail.trimmed.isEmpty
    }

    private var canTestSlack: Bool {
        !slackBotToken.trimmed.isEmpty && !notifyEmail.trimmed.isEmpty
    }

    var body: some View {
        Form {
            Section {
                SecureField("Teamwork API token", text: $token)
                TextField("https://yourcompany.teamwork.com", text: $siteURL)
            } header: {
                Text("Teamwork")
            }

            Section {
                SecureField("Slack bot token (xoxb-…)", text: $slackBotToken)
                TextField("Your Slack email", text: $notifyEmail)
                HStack {
                    Button {
                        testSlack()
                    } label: {
                        if isTesting {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Sending…")
                            }
                        } else {
                            Text("Send test DM")
                        }
                    }
                    .disabled(isTesting || !canTestSlack)

                    if let testResult {
                        Label(testResult.message, systemImage: testResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testResult.ok ? .green : .red)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Slack")
            } footer: {
                Text("Notifications are sent as a direct message to the person with this email. The bot token needs the chat:write and users:read.email scopes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ignore comments from me", isOn: $store.ignoreOwnComments)
            } header: {
                Text("Filtering")
            } footer: {
                Text("When on, comments you post yourself won't trigger a Slack alert. Your identity is detected from your Teamwork token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if savedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear(perform: loadCurrent)
    }

    private func loadCurrent() {
        token = store.apiToken
        siteURL = store.siteURL
        slackBotToken = store.slackBotToken
        notifyEmail = store.notifyEmail
    }

    /// Send a one-off DM using the values currently in the form, surfacing the
    /// exact Slack error inline so no Console digging is needed.
    private func testSlack() {
        testResult = nil
        let slack = SlackAPI(botToken: slackBotToken.trimmed)
        let email = notifyEmail.trimmed
        isTesting = true

        Task {
            defer { isTesting = false }
            do {
                let memberId = try await slack.lookupUserId(email: email)
                try await slack.postMessage(
                    channel: memberId,
                    text: "*TaskWatch* ✅ Test message — Slack notifications are working."
                )
                testResult = (true, "Sent! Check your Slack DMs.")
            } catch let error as SlackError {
                testResult = (false, error.errorDescription ?? "Slack error.")
            } catch {
                testResult = (false, error.localizedDescription)
            }
        }
    }

    private func save() {
        store.saveCredentials(
            token: token,
            siteURL: siteURL,
            slackBotToken: slackBotToken,
            notifyEmail: notifyEmail
        )
        withAnimation { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedConfirmation = false }
        }
    }
}
