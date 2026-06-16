import Foundation

/// Errors from the Slack Web API. Slack returns HTTP 200 with `"ok": false`
/// and an `error` string, so we surface that string.
enum SlackError: LocalizedError {
    case http(status: Int)
    case api(String)
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .http(let status):
            return "Slack returned HTTP \(status)."
        case .api(let code):
            switch code {
            case "users_not_found":
                return "No Slack user found for that email."
            case "invalid_auth", "not_authed", "token_revoked", "account_inactive":
                return "Slack bot token is invalid or revoked."
            case "missing_scope":
                return "The Slack app is missing a required scope (chat:write / users:read.email)."
            default:
                return "Slack error: \(code)"
            }
        case .network(let message):
            return message
        case .decoding:
            return "Couldn't read Slack's response."
        }
    }
}

/// Thin client over the Slack Web API using a bot token (`xoxb-…`).
/// Used to DM each user individually (no shared channel).
struct SlackAPI {
    let botToken: String

    private static let base = URL(string: "https://slack.com/api/")!

    /// Resolve a Slack member id from an email address. Requires the
    /// `users:read.email` scope on the Slack app.
    func lookupUserId(email: String) async throws -> String {
        var components = URLComponents(
            url: Self.base.appendingPathComponent("users.lookupByEmail"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "email", value: email)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")

        let response: LookupResponse = try await send(request)
        guard let id = response.user?.id else { throw SlackError.api(response.error ?? "unknown") }
        return id
    }

    /// Post a message to a channel or user id. Passing a user id (`U…`) DMs them.
    /// Requires the `chat:write` scope.
    func postMessage(channel: String, text: String) async throws {
        var request = URLRequest(url: Self.base.appendingPathComponent("chat.postMessage"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "channel": channel,
            "text": text,
            "unfurl_links": false,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let _: PostMessageResponse = try await send(request)
    }

    // MARK: - Plumbing

    private func send<T: SlackResponse>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SlackError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SlackError.http(status: http.statusCode)
        }

        let decoded: T
        do {
            decoded = try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SlackError.decoding
        }

        guard decoded.ok else { throw SlackError.api(decoded.error ?? "unknown") }
        return decoded
    }
}

// MARK: - Response shapes

private protocol SlackResponse: Decodable {
    var ok: Bool { get }
    var error: String? { get }
}

private struct LookupResponse: SlackResponse {
    let ok: Bool
    let error: String?
    let user: User?

    struct User: Decodable { let id: String }
}

private struct PostMessageResponse: SlackResponse {
    let ok: Bool
    let error: String?
}
