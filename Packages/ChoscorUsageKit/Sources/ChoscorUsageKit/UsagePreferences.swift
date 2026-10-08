// User preferences: refresh interval and notification toggles, stored in UserDefaults.
import ChoscorUsageCore

/// Settings shown on the General tab.
public struct UsagePreferences: Equatable, Sendable {
    /// Automatic refresh interval.
    public var refreshInterval: RefreshInterval
    /// Whether 80%/95% alerts are delivered.
    public var thresholdAlertsEnabled: Bool
    /// Whether window-reset alerts are delivered.
    public var resetAlertsEnabled: Bool

    /// Creates preferences; defaults are a 5-minute interval with both alert kinds on.
    public init(
        refreshInterval: RefreshInterval = .default, thresholdAlertsEnabled: Bool = true,
        resetAlertsEnabled: Bool = true
    ) {
        self.refreshInterval = refreshInterval
        self.thresholdAlertsEnabled = thresholdAlertsEnabled
        self.resetAlertsEnabled = resetAlertsEnabled
    }

    /// Whether any notification kind is on, which is when the app asks for permission.
    public var notificationsEnabled: Bool { thresholdAlertsEnabled || resetAlertsEnabled }
}
