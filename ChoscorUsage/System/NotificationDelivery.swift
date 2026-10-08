// Delivers Kit's usage notifications through UNUserNotificationCenter.
import ChoscorUsageKit
import UserNotifications
import os

/// Posts alerts; text contains only a display name, window label and percentage.
struct NotificationDelivery: UsageNotifying {
    private static let logger = Logger(subsystem: "com.choscor.ChoscorUsage", category: "notifications")

    /// Asks for alert and sound permission; the system shows the prompt only once.
    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deliver(_ notifications: [UsageNotification]) async {
        let center = UNUserNotificationCenter.current()
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                Self.logger.error("Posting a notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
