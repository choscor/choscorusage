// Formats countdowns and ages compactly for the menu, such as `1h12m` and `3d4h`.
import Foundation

/// Two-unit duration text that fits a single menu line.
public enum CompactDuration {
    private static let units: [(seconds: Int, suffix: String)] = [(86_400, "d"), (3_600, "h"), (60, "m")]

    /// Returns the two largest non-zero units (`3d4h`, `1h12m`, `5d`), or `<1m` under a minute.
    public static func format(_ seconds: TimeInterval) -> String {
        var remaining = Int(seconds.rounded(.down))
        var parts: [String] = []
        for unit in units where parts.count < 2 {
            let value = remaining / unit.seconds
            remaining %= unit.seconds
            if value > 0 {
                parts.append("\(value)\(unit.suffix)")
            } else if !parts.isEmpty {
                break
            }
        }
        return parts.isEmpty ? "<1m" : parts.joined()
    }

    /// Returns `just now` under a minute, else `<duration> ago`.
    public static func age(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "just now" : "\(format(seconds)) ago"
    }
}
