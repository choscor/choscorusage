// Decodes the undocumented Claude usage response into normalized windows.
import ChoscorUsageCore
import Foundation

/// Decoder for `GET https://api.anthropic.com/api/oauth/usage`.
///
/// Undocumented by Anthropic; shape from https://github.com/steipete/CodexBar/blob/main/docs/claude.md
/// (verified 2026-10-08). Known windows are `five_hour`, `seven_day`, `seven_day_opus` and
/// `seven_day_sonnet`, each `{utilization: 0–100, resets_at: ISO 8601}` or `null`; a window whose
/// `utilization` is `null` has no data yet and is omitted. Unknown fields and unknown top-level
/// objects are ignored, even window-shaped ones: their keys are internal codenames (such as
/// `iguana_necktie`) that mean nothing to the user. The newer `limits[]` array and `extra_usage`
/// are read by ``ClaudeLimitsDecoder``; a `limits[]` window replaces the flat window with the same ID.
public enum ClaudeUsageDecoder {
    /// The body is not a JSON object or a window has unexpected types.
    public struct DecodingFailure: Error, Equatable {}

    private static let known: [(key: String, label: String, seconds: Int)] = [
        ("five_hour", "5h", 18_000),
        ("seven_day", "7d", 604_800),
        ("seven_day_opus", "7d Opus", 604_800),
        ("seven_day_sonnet", "7d Sonnet", 604_800),
    ]

    /// Returns known windows in fixed order (each taken from `limits[]` when listed there), then
    /// other `limits[]` windows, and `Extra`. Reset times outside ``ResetDateRange`` of `now` are
    /// dropped. Throws ``DecodingFailure`` when the response no longer matches.
    public static func decode(_ data: Data, now: Date) throws(DecodingFailure) -> [UsageWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DecodingFailure()
        }
        var limits = ClaudeLimitsDecoder.limitWindows(in: root, now: now)
        var windows: [UsageWindow] = []
        for entry in known {
            if let index = limits.firstIndex(where: { $0.id == entry.key }) {
                windows.append(limits.remove(at: index))
                continue
            }
            guard let object = root[entry.key] as? [String: Any], !(object["utilization"] is NSNull) else {
                continue
            }
            windows.append(try window(entry.key, entry.label, .seconds(entry.seconds), object, now: now))
        }
        windows += limits
        if let extra = ClaudeLimitsDecoder.extraUsageWindow(in: root) {
            windows.append(extra)
        }
        return windows
    }

    private static func window(
        _ id: String, _ label: String, _ length: Duration, _ object: [String: Any], now: Date
    )
        throws(DecodingFailure) -> UsageWindow
    {
        guard let utilization = object["utilization"] as? NSNumber else {
            throw DecodingFailure()
        }
        var resetsAt: Date?
        switch object["resets_at"] {
        case nil, is NSNull:
            resetsAt = nil
        case let text as String:
            guard let date = ISO8601Timestamp.parse(text) else {
                throw DecodingFailure()
            }
            resetsAt = ResetDateRange.accepted(date, now: now)
        default:
            throw DecodingFailure()
        }
        return UsageWindow(
            id: id, label: label, usedPercent: utilization.doubleValue, resetsAt: resetsAt, windowLength: length)
    }
}
