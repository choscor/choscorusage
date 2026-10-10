// Bounds the reset times decoders accept, so corrupt or hostile values never reach date math.
import Foundation

/// The span a window's reset time must fall in: ten years either side of when it was decoded.
///
/// Real windows reset within about a month; the wide margin only keeps broken values (such as
/// `1e20` epoch seconds) out of countdowns and notification IDs, where they could trap.
public enum ResetDateRange {
    /// Ten 365-day years in seconds; the exact length does not matter.
    public static let margin: TimeInterval = 10 * 365 * 86_400

    /// Returns `date` when it lies within ``margin`` of `now`, else `nil`. Non-finite dates are
    /// rejected. Pure; any thread.
    public static func accepted(_ date: Date?, now: Date) -> Date? {
        guard let date, abs(date.timeIntervalSince(now)) <= margin else {
            return nil
        }
        return date
    }

    /// Returns the date `seconds` after the Unix epoch when it is within ``margin`` of `now`,
    /// else `nil`. Pure; any thread.
    public static func date(epochSeconds seconds: Double, now: Date) -> Date? {
        accepted(Date(timeIntervalSince1970: seconds), now: now)
    }
}
