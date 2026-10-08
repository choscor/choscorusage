// Turns a window length into the short and spoken labels shown for it.

/// Labels come from the window length, never from assumptions about a plan: one Codex plan
/// reported a 43,200-minute primary window, so `5h`/`7d` cannot be hard-coded.
public enum WindowLabel {
    private static let minute = 60
    private static let hour = 3_600
    private static let day = 86_400

    /// Returns a compact label: `5h`, `7d`, `30d`, `1h30m` or `45m`.
    public static func short(forSeconds seconds: Int) -> String {
        if seconds >= day && seconds.isMultiple(of: day) {
            return "\(seconds / day)d"
        }
        if seconds >= hour && seconds.isMultiple(of: hour) {
            return "\(seconds / hour)h"
        }
        if seconds > hour {
            return "\(seconds / hour)h\((seconds % hour) / minute)m"
        }
        return "\(max(seconds / minute, 1))m"
    }

    /// Returns a VoiceOver phrase such as `5 hour` or `7 day`, used as "… of 5 hour limit".
    public static func spoken(forSeconds seconds: Int) -> String {
        if seconds >= day && seconds.isMultiple(of: day) {
            return "\(seconds / day) day"
        }
        if seconds >= hour && seconds.isMultiple(of: hour) {
            return "\(seconds / hour) hour"
        }
        return "\(max(seconds / minute, 1)) minute"
    }
}
