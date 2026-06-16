import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter for the local toast shown when a watched
/// task is completed and removed from the list.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    NSLog("[TaskWatch] Notification auth error: \(error.localizedDescription)")
                } else if !granted {
                    NSLog("[TaskWatch] Notification permission not granted")
                }
            }
    }

    static func taskCompleted(taskName: String) {
        let content = UNMutableNotificationContent()
        content.title = "TaskWatch"
        content.body = "\(taskName) is complete and has been removed from your watch list."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[TaskWatch] Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}
