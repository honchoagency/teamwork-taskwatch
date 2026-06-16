import Foundation
import Security

/// Minimal Keychain wrapper for the app's secrets, each stored as a generic
/// password item keyed by account. Secrets (Teamwork API token, Slack bot
/// token) live here; non-secret prefs (site URL, email) live in UserDefaults.
enum Keychain {
    private static let service = "agency.honcho.TaskWatch"

    /// Known secret accounts.
    enum Account: String {
        case teamworkToken = "teamwork-api-token"
        case slackBotToken = "slack-bot-token"
    }

    static func save(_ value: String, for account: Account) {
        guard let data = value.data(using: .utf8) else { return }

        // Remove any existing item first so we always overwrite cleanly.
        delete(account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[TaskWatch] Keychain save failed for \(account.rawValue): \(status)")
        }
    }

    static func load(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
