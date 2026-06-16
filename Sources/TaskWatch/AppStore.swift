import Foundation
import Combine

/// Central observable state: watched tasks, preferences, and credential access.
/// Watched tasks and non-secret preferences live in UserDefaults; the API token
/// lives in the Keychain.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    static let maxWatchedTasks = 10

    @Published private(set) var tasks: [WatchedTask] = []
    @Published var siteURL: String
    /// Email of the person to DM in Slack (resolved to a member id).
    @Published var notifyEmail: String
    /// In-memory mirror of the Keychain Teamwork token, published so views react.
    @Published var apiToken: String
    /// In-memory mirror of the Keychain Slack bot token (`xoxb-…`).
    @Published var slackBotToken: String

    /// When true, comments authored by the authenticated user are not alerted.
    @Published var ignoreOwnComments: Bool {
        didSet { defaults.set(ignoreOwnComments, forKey: Keys.ignoreOwnComments) }
    }

    /// Cached Teamwork person id of the authenticated user, resolved lazily via
    /// `/me.json`. Cleared whenever credentials change.
    private(set) var currentUserId: String? {
        didSet { defaults.set(currentUserId, forKey: Keys.currentUserId) }
    }

    /// Cached Slack member id for `notifyEmail`, resolved lazily via
    /// `users.lookupByEmail`. Cleared whenever the email or token changes.
    private(set) var slackMemberId: String? {
        didSet { defaults.set(slackMemberId, forKey: Keys.slackMemberId) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let tasks = "watchedTasks"
        static let siteURL = "teamworkSiteURL"
        static let notifyEmail = "notifyEmail"
        static let ignoreOwnComments = "ignoreOwnComments"
        static let currentUserId = "currentUserId"
        static let slackMemberId = "slackMemberId"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.siteURL = defaults.string(forKey: Keys.siteURL) ?? ""
        self.notifyEmail = defaults.string(forKey: Keys.notifyEmail) ?? ""
        self.apiToken = Keychain.load(.teamworkToken) ?? ""
        self.slackBotToken = Keychain.load(.slackBotToken) ?? ""
        self.ignoreOwnComments = defaults.bool(forKey: Keys.ignoreOwnComments)
        self.currentUserId = defaults.string(forKey: Keys.currentUserId)
        self.slackMemberId = defaults.string(forKey: Keys.slackMemberId)
        self.tasks = Self.loadTasks(from: defaults)
    }

    // MARK: - Credentials

    var hasCredentials: Bool {
        !apiToken.trimmed.isEmpty
            && !siteURL.trimmed.isEmpty
            && !slackBotToken.trimmed.isEmpty
            && !notifyEmail.trimmed.isEmpty
    }

    /// Persist all credentials. Tokens go to Keychain; site + email to UserDefaults.
    func saveCredentials(token: String, siteURL: String, slackBotToken: String, notifyEmail: String) {
        let token = token.trimmed
        let site = siteURL.trimmed
        let slack = slackBotToken.trimmed
        let email = notifyEmail.trimmed

        Keychain.save(token, for: .teamworkToken)
        Keychain.save(slack, for: .slackBotToken)
        defaults.set(site, forKey: Keys.siteURL)
        defaults.set(email, forKey: Keys.notifyEmail)

        self.apiToken = token
        self.siteURL = site
        self.slackBotToken = slack
        self.notifyEmail = email

        // Credentials changed — drop cached identities so they re-resolve.
        self.currentUserId = nil
        self.slackMemberId = nil
    }

    func setCurrentUserId(_ id: String) {
        currentUserId = id
    }

    func setSlackMemberId(_ id: String) {
        slackMemberId = id
    }

    /// Build a Teamwork client from current credentials, or nil if missing.
    func makeAPIClient() -> TeamworkAPI? {
        let token = apiToken.trimmed
        let site = siteURL.trimmed
        guard !token.isEmpty, !site.isEmpty else { return nil }
        return TeamworkAPI(siteURL: site, apiToken: token)
    }

    /// Build a Slack client from the bot token, or nil if missing.
    func makeSlackAPI() -> SlackAPI? {
        let token = slackBotToken.trimmed
        guard !token.isEmpty else { return nil }
        return SlackAPI(botToken: token)
    }

    // MARK: - Watched tasks

    var isAtCapacity: Bool { tasks.count >= Self.maxWatchedTasks }

    func contains(taskId: String) -> Bool {
        tasks.contains { $0.taskId == taskId }
    }

    func addTask(_ task: WatchedTask) {
        guard !isAtCapacity, !contains(taskId: task.taskId) else { return }
        tasks.append(task)
        persistTasks()
    }

    func removeTask(taskId: String) {
        tasks.removeAll { $0.taskId == taskId }
        persistTasks()
    }

    func updateLastSeen(taskId: String, commentId: String) {
        guard let idx = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        tasks[idx].lastSeenCommentId = commentId
        persistTasks()
    }

    /// Backfill / refresh a task's project name (and name) from a fresh fetch.
    func updateMetadata(taskId: String, taskName: String?, projectName: String?) {
        guard let idx = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        var changed = false
        if let projectName, !projectName.isEmpty, tasks[idx].projectName != projectName {
            tasks[idx].projectName = projectName
            changed = true
        }
        if let taskName, !taskName.isEmpty, tasks[idx].taskName != taskName {
            tasks[idx].taskName = taskName
            changed = true
        }
        if changed { persistTasks() }
    }

    /// Backfill / refresh a task's project name (e.g. for tasks added before
    /// it was tracked, or after a project rename). No-op if unchanged.
    func updateProjectName(taskId: String, projectName: String?) {
        guard let idx = tasks.firstIndex(where: { $0.taskId == taskId }),
              tasks[idx].projectName != projectName else { return }
        tasks[idx].projectName = projectName
        persistTasks()
    }

    // MARK: - Persistence

    private func persistTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        defaults.set(data, forKey: Keys.tasks)
    }

    private static func loadTasks(from defaults: UserDefaults) -> [WatchedTask] {
        guard let data = defaults.data(forKey: Keys.tasks),
              let tasks = try? JSONDecoder().decode([WatchedTask].self, from: data) else {
            return []
        }
        return tasks
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
