import Foundation

/// Errors surfaced to the UI when adding a task. Polling swallows errors instead.
enum TeamworkError: LocalizedError {
    case invalidURL
    case badResponse(status: Int)
    case decoding
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a Teamwork task URL."
        case .badResponse(let status):
            return status == 401
                ? "Authentication failed — check your API token."
                : "Teamwork returned an error (HTTP \(status))."
        case .decoding:
            return "Couldn't read Teamwork's response."
        case .network(let message):
            return message
        }
    }
}

/// Thin client over Teamwork's classic JSON API using HTTP Basic auth
/// (API token as username, "X" as password).
struct TeamworkAPI {
    let baseURL: URL
    private let authHeader: String

    /// - Parameter siteURL: e.g. "https://yourcompany.teamwork.com"
    init?(siteURL: String, apiToken: String) {
        var trimmed = siteURL.trimmed
        if !trimmed.lowercased().hasPrefix("http") {
            trimmed = "https://" + trimmed
        }
        // Strip any trailing slash so path joins are predictable.
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        guard let url = URL(string: trimmed) else { return nil }
        self.baseURL = url

        let raw = "\(apiToken):X"
        self.authHeader = "Basic " + Data(raw.utf8).base64EncodedString()
    }

    // MARK: - Endpoints

    func fetchTask(taskId: String) async throws -> TodoItem {
        let url = baseURL.appendingPathComponent("tasks/\(taskId).json")
        let response: TaskResponse = try await get(url)
        return response.todoItem
    }

    func fetchComments(taskId: String) async throws -> [Comment] {
        let url = baseURL.appendingPathComponent("tasks/\(taskId)/comments.json")
        let response: CommentsResponse = try await get(url)
        return response.comments
    }

    /// The authenticated user's Teamwork person id (for ignoring own comments).
    func fetchCurrentUserId() async throws -> String {
        let url = baseURL.appendingPathComponent("me.json")
        let response: MeResponse = try await get(url)
        return response.person.id
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TeamworkError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw TeamworkError.badResponse(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TeamworkError.decoding
        }
    }

    // MARK: - URL parsing

    /// Extract the numeric task id from a pasted Teamwork task URL.
    /// Handles forms like:
    ///   https://co.teamwork.com/tasks/12345
    ///   https://co.teamwork.com/app/tasks/12345
    ///   https://co.teamwork.com/#/tasks/12345?c=1
    /// and a bare id ("12345").
    static func parseTaskId(from input: String) -> String? {
        let trimmed = input.trimmed
        guard !trimmed.isEmpty else { return nil }

        // Bare numeric id.
        if trimmed.allSatisfy({ $0.isNumber }) { return trimmed }

        // Look for "tasks/<digits>" anywhere in the string.
        if let range = trimmed.range(of: #"tasks/(\d+)"#, options: .regularExpression) {
            let match = String(trimmed[range])
            let digits = match.dropFirst("tasks/".count)
            return digits.isEmpty ? nil : String(digits)
        }

        return nil
    }
}
