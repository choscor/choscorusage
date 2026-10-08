// Loads and saves UsagePreferences in a UserDefaults domain. Holds no secrets.
import ChoscorUsageCore
import Foundation

/// Persists preferences under fixed keys; missing or invalid values fall back to defaults.
public struct PreferencesStore: @unchecked Sendable {
    // UserDefaults is documented as thread-safe; it is only read and written here.
    private let defaults: UserDefaults

    private enum Key {
        static let interval = "refreshIntervalMinutes"
        static let thresholds = "thresholdAlertsEnabled"
        static let resets = "resetAlertsEnabled"
        static let chosenProfile = "chosenProfileID"
    }

    /// Creates a store over `defaults`.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Returns stored preferences, using defaults for anything missing or invalid.
    public func load() -> UsagePreferences {
        var preferences = UsagePreferences()
        if let interval = RefreshInterval(rawValue: defaults.integer(forKey: Key.interval)) {
            preferences.refreshInterval = interval
        }
        if defaults.object(forKey: Key.thresholds) != nil {
            preferences.thresholdAlertsEnabled = defaults.bool(forKey: Key.thresholds)
        }
        if defaults.object(forKey: Key.resets) != nil {
            preferences.resetAlertsEnabled = defaults.bool(forKey: Key.resets)
        }
        preferences.chosenProfileID = defaults.string(forKey: Key.chosenProfile).flatMap(UUID.init(uuidString:))
        return preferences
    }

    /// Stores `preferences`.
    public func save(_ preferences: UsagePreferences) {
        defaults.set(preferences.refreshInterval.rawValue, forKey: Key.interval)
        defaults.set(preferences.thresholdAlertsEnabled, forKey: Key.thresholds)
        defaults.set(preferences.resetAlertsEnabled, forKey: Key.resets)
        defaults.set(preferences.chosenProfileID?.uuidString, forKey: Key.chosenProfile)
    }
}
