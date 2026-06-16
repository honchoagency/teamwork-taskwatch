import Foundation

/// Formats and sends new-comment alerts as a Slack DM via the bot API.
enum SlackNotifier {
    /// Build the Slack message text for a new comment. Kept separate so it can
    /// be unit-checked and reused.
    static func message(for task: WatchedTask, comment: Comment) -> String {
        let snippet = (comment.body ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(200)
        let ellipsis = (comment.body ?? "").count > 200 ? "..." : ""
        let author = comment.authorName.isEmpty ? "Unknown" : comment.authorName

        // Project line only appears when we know the project name (older watched
        // tasks backfill it on the next poll).
        let projectLine: String
        if let project = task.projectName, !project.isEmpty {
            projectLine = "\n*Project:* \(project)"
        } else {
            projectLine = ""
        }

        return """
        *New comment on <\(task.taskUrl)|\(task.taskName)>*\(projectLine)
        *From:* \(author)
        *Comment:* \(snippet)\(ellipsis)
        <\(task.taskUrl)|View task>
        """
    }

    /// DM the user about a new comment. Failures are logged only — polling must
    /// never throw on Slack errors.
    static func notifyNewComment(
        slack: SlackAPI,
        channelId: String,
        task: WatchedTask,
        comment: Comment
    ) async {
        do {
            try await slack.postMessage(channel: channelId, text: message(for: task, comment: comment))
        } catch {
            NSLog("[TaskWatch] Slack DM failed: \(error.localizedDescription)")
        }
    }
}
