import Foundation
import Combine
import AppKit

/// Checks GitHub Releases for a newer version and publishes it so the UI can
/// surface an "update available" prompt. Mirrors the BBC Radio 6 Music approach.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// The latest release version, if it's newer than what's running. Else nil.
    @Published private(set) var availableVersion: String?

    static let repo = "honchoagency/teamwork-taskwatch"
    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(repo)/releases/latest")!
    }

    private let currentVersion: String
    private let releasesAPI = URL(string: "https://api.github.com/repos/\(UpdateChecker.repo)/releases/latest")!
    private var timer: Timer?
    private var prefsCancellable: AnyCancellable?

    private init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        // Clear the prompt immediately if the user turns the feature off.
        prefsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.isEnabled { self.availableVersion = nil }
            }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true
    }

    func start() {
        check()
        // Re-check once a day while running.
        timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func check() {
        guard isEnabled else {
            availableVersion = nil
            return
        }
        Task { await performCheck() }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPageURL)
    }

    private func performCheck() async {
        var request = URLRequest(url: releasesAPI)
        request.setValue("TaskWatch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                NSLog("[TaskWatch] Update check: no tag_name in response (private repo without auth?)")
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            availableVersion = isNewer(latest, than: currentVersion) ? latest : nil
        } catch {
            NSLog("[TaskWatch] Update check failed: \(error.localizedDescription)")
        }
    }

    /// Numeric, dot-separated version comparison (e.g. "1.2.10" > "1.2.9").
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let parts = { (v: String) in v.split(separator: ".").compactMap { Int($0) } }
        let a = parts(candidate)
        let b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
