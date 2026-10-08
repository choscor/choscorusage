// The automatic refresh intervals offered in Settings.

/// How often profiles refresh automatically.
public enum RefreshInterval: Int, CaseIterable, Codable, Sendable, Identifiable {
    /// Every minute.
    case oneMinute = 1
    /// Every two minutes.
    case twoMinutes = 2
    /// Every five minutes; the default.
    case fiveMinutes = 5
    /// Every ten minutes.
    case tenMinutes = 10

    /// The default interval.
    public static let `default` = Self.fiveMinutes

    /// The interval in minutes, used as the identity in pickers.
    public var id: Int { rawValue }

    /// The interval as a duration.
    public var duration: Duration { .seconds(rawValue * 60) }
}
