// Parses one Codex session-log line into rate-limit windows.
import ChoscorUsageCore
import Foundation

/// A `token_count` event with non-null `rate_limits`.
internal struct CodexLogLine {
    internal let timestamp: Date?
    internal let windows: [UsageWindow]

    /// Returns the parsed event, or `nil` for other lines, malformed JSON or null rate limits.
    /// Reset times outside ``ResetDateRange`` of `now` and window lengths that overflow are dropped.
    internal static func parse(_ line: Data, now: Date) -> Self? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
            let payload = object["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let limits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }
        let timestamp = (object["timestamp"] as? String).flatMap(ISO8601Timestamp.parse)
        let windows = [("primary", "primary_window"), ("secondary", "secondary_window")].compactMap { key, id in
            (limits[key] as? [String: Any]).flatMap { window(id: id, $0, loggedAt: timestamp, now: now) }
        }
        guard !windows.isEmpty else {
            return nil
        }
        return Self(timestamp: timestamp, windows: windows)
    }

    /// Older Codex versions logged `resets_in_seconds`, relative to the line's timestamp, instead
    /// of `resets_at` (openai/codex `RateLimitWindow` history, verified 2026-10-08).
    private static func window(id: String, _ object: [String: Any], loggedAt: Date?, now: Date) -> UsageWindow? {
        guard let used = object["used_percent"] as? NSNumber else {
            return nil
        }
        let seconds = (object["window_minutes"] as? NSNumber).flatMap(windowSeconds(minutes:))
        let resetsIn = (object["resets_in_seconds"] as? NSNumber).flatMap { delay in
            loggedAt.flatMap { ResetDateRange.accepted($0.addingTimeInterval(delay.doubleValue), now: now) }
        }
        let resetsAt =
            (object["resets_at"] as? NSNumber).flatMap { ResetDateRange.date(epochSeconds: $0.doubleValue, now: now) }
            ?? resetsIn
        return UsageWindow(
            id: id,
            label: seconds.map { WindowLabel.short(forSeconds: $0) } ?? id,
            usedPercent: used.doubleValue,
            resetsAt: resetsAt,
            windowLength: seconds.map { .seconds($0) })
    }

    /// A positive whole number of minutes in seconds; `nil` when the value is fractional,
    /// non-positive or would overflow `Int`, which `* 60` would trap on.
    private static func windowSeconds(minutes: NSNumber) -> Int? {
        guard let whole = Int(exactly: minutes.doubleValue), whole > 0 else {
            return nil
        }
        let (seconds, overflow) = whole.multipliedReportingOverflow(by: 60)
        return overflow ? nil : seconds
    }
}
