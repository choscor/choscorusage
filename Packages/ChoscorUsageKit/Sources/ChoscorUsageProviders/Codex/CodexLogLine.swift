// Parses one Codex session-log line into rate-limit windows.
import ChoscorUsageCore
import Foundation

/// A `token_count` event with non-null `rate_limits`.
internal struct CodexLogLine {
    internal let timestamp: Date?
    internal let windows: [UsageWindow]

    /// Returns the parsed event, or `nil` for other lines, malformed JSON or null rate limits.
    internal static func parse(_ line: Data) -> Self? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
            let payload = object["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let limits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }
        let timestamp = (object["timestamp"] as? String).flatMap(ISO8601Timestamp.parse)
        let windows = [("primary", "primary_window"), ("secondary", "secondary_window")].compactMap { key, id in
            (limits[key] as? [String: Any]).flatMap { window(id: id, $0, loggedAt: timestamp) }
        }
        guard !windows.isEmpty else {
            return nil
        }
        return Self(timestamp: timestamp, windows: windows)
    }

    /// Older Codex versions logged `resets_in_seconds`, relative to the line's timestamp, instead
    /// of `resets_at` (openai/codex `RateLimitWindow` history, verified 2026-10-08).
    private static func window(id: String, _ object: [String: Any], loggedAt: Date?) -> UsageWindow? {
        guard let used = object["used_percent"] as? NSNumber else {
            return nil
        }
        let seconds = (object["window_minutes"] as? NSNumber).map { $0.intValue * 60 }
        let resetsIn = (object["resets_in_seconds"] as? NSNumber).flatMap { delay in
            loggedAt.map { $0.addingTimeInterval(delay.doubleValue) }
        }
        let resetsAt =
            (object["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? resetsIn
        return UsageWindow(
            id: id,
            label: seconds.map { WindowLabel.short(forSeconds: $0) } ?? id,
            usedPercent: used.doubleValue,
            resetsAt: resetsAt,
            windowLength: seconds.map { .seconds($0) })
    }
}
