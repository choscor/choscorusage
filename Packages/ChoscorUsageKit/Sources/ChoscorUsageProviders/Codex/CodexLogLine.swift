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
        let windows = [("primary", "primary_window"), ("secondary", "secondary_window")].compactMap { key, id in
            (limits[key] as? [String: Any]).flatMap { window(id: id, $0) }
        }
        guard !windows.isEmpty else {
            return nil
        }
        return Self(timestamp: (object["timestamp"] as? String).flatMap(ISO8601Timestamp.parse), windows: windows)
    }

    private static func window(id: String, _ object: [String: Any]) -> UsageWindow? {
        guard let used = object["used_percent"] as? NSNumber else {
            return nil
        }
        let seconds = (object["window_minutes"] as? NSNumber).map { $0.intValue * 60 }
        let resetsAt = (object["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return UsageWindow(
            id: id,
            label: seconds.map { WindowLabel.short(forSeconds: $0) } ?? id,
            usedPercent: used.doubleValue,
            resetsAt: resetsAt,
            windowLength: seconds.map { .seconds($0) })
    }
}
