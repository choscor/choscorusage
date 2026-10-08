// User preferences: refresh interval, notification toggles and the menu bar's chosen profile.
import ChoscorUsageCore
import Foundation

/// Settings shown on the General tab.
public struct UsagePreferences: Equatable, Sendable {
    /// Automatic refresh interval.
    public var refreshInterval: RefreshInterval
    /// Whether 80%/95% alerts are delivered.
    public var thresholdAlertsEnabled: Bool
    /// Whether window-reset alerts are delivered.
    public var resetAlertsEnabled: Bool
    /// The profile the menu bar shows in full, or `nil` to show the worst percentage.
    public var chosenProfileID: UUID?

    /// Creates preferences; defaults are a 5-minute interval, both alert kinds on and no chosen profile.
    public init(
        refreshInterval: RefreshInterval = .default, thresholdAlertsEnabled: Bool = true,
        resetAlertsEnabled: Bool = true, chosenProfileID: UUID? = nil
    ) {
        self.refreshInterval = refreshInterval
        self.thresholdAlertsEnabled = thresholdAlertsEnabled
        self.resetAlertsEnabled = resetAlertsEnabled
        self.chosenProfileID = chosenProfileID
    }

    /// Whether any notification kind is on, which is when the app asks for permission.
    public var notificationsEnabled: Bool { thresholdAlertsEnabled || resetAlertsEnabled }
}
