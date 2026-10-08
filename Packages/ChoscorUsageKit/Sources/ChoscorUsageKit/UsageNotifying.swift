// The seam through which Kit hands notifications to the app's delivery code.
import ChoscorUsageCore

/// Delivers notifications; the app implements it with UNUserNotificationCenter.
public protocol UsageNotifying: Sendable {
    /// Delivers `notifications`, each carrying only display-safe text.
    func deliver(_ notifications: [UsageNotification]) async
}
