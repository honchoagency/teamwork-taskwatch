import Foundation

// MARK: - Watched task

/// A Teamwork task the user is watching. Persisted to UserDefaults.
struct WatchedTask: Codable, Identifiable, Equatable {
    var taskId: String
    var taskName: String
    var taskUrl: String
    var projectName: String?
    /// The id of the most recent comment we have already seen. Used as the
    /// baseline so we never alert on comments that existed when the task was added.
    var lastSeenCommentId: String?

    var id: String { taskId }
}

// MARK: - Teamwork API responses
//
// Teamwork's classic JSON API uses hyphenated keys (e.g. "todo-item",
// "author-firstname"), so each decodable maps them explicitly.

/// Response from `GET /tasks/{id}.json`.
struct TaskResponse: Decodable {
    let todoItem: TodoItem

    enum CodingKeys: String, CodingKey {
        case todoItem = "todo-item"
    }
}

struct TodoItem: Decodable {
    let content: String?
    let status: String?
    let projectName: String?

    enum CodingKeys: String, CodingKey {
        case content
        case status
        case projectName = "project-name"
    }
}

/// Response from `GET /tasks/{id}/comments.json`.
struct CommentsResponse: Decodable {
    let comments: [Comment]
}

struct Comment: Decodable {
    let id: String
    let body: String?
    let authorId: String?
    let authorFirstname: String?
    let authorLastname: String?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case authorId = "author-id"
        case authorFirstname = "author-firstname"
        case authorLastname = "author-lastname"
    }

    // Teamwork encodes ids as either a number or a string depending on endpoint,
    // so decode them defensively into Strings either way.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeId(container, forKey: .id) ?? ""
        authorId = Self.decodeId(container, forKey: .authorId)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        authorFirstname = try container.decodeIfPresent(String.self, forKey: .authorFirstname)
        authorLastname = try container.decodeIfPresent(String.self, forKey: .authorLastname)
    }

    private static func decodeId(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let intId = try? container.decode(Int.self, forKey: key) {
            return String(intId)
        }
        return try? container.decode(String.self, forKey: key)
    }

    var authorName: String {
        [authorFirstname, authorLastname]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Response from `GET /me.json` — used to identify the authenticated user so
/// their own comments can be ignored.
struct MeResponse: Decodable {
    let person: Person

    struct Person: Decodable {
        let id: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let intId = try? container.decode(Int.self, forKey: .id) {
                id = String(intId)
            } else {
                id = try container.decode(String.self, forKey: .id)
            }
        }

        enum CodingKeys: String, CodingKey { case id }
    }
}

// MARK: - Comment ordering helpers

extension Array where Element == Comment {
    /// The numerically-newest comment, or nil if the list is empty.
    var newest: Comment? {
        self.max { ($0.id.asCommentInt) < ($1.id.asCommentInt) }
    }
}

extension String {
    /// Comment / task ids are numeric in Teamwork. Parse for ordering;
    /// fall back to 0 so a malformed id never crashes a comparison.
    var asCommentInt: Int { Int(self) ?? 0 }
}
