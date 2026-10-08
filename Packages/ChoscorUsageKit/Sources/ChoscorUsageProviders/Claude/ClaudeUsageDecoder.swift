// Decodes the undocumented Claude usage response into normalized windows.
import ChoscorUsageCore
import Foundation

/// Decoder for `GET https://api.anthropic.com/api/oauth/usage`.
///
/// Undocumented by Anthropic; shape from https://github.com/steipete/CodexBar/blob/main/docs/claude.md
/// (verified 2026-10-08). Known windows are `five_hour`, `seven_day`, `seven_day_opus` and
/// `seven_day_sonnet`, each `{utilization: 0–100, resets_at: ISO 8601}` or `null`; a window whose
/// `utilization` is `null` has no data yet and is omitted. Unknown fields
/// are ignored; unknown top-level objects with that same shape become extra windows labelled
/// with their key.
public enum ClaudeUsageDecoder {
    /// The body is not a JSON object or a window has unexpected types.
    public struct DecodingFailure: Error, Equatable {}

    private static let known: [(key: String, label: String, seconds: Int)] = [
        ("five_hour", "5h", 18_000),
        ("seven_day", "7d", 604_800),
        ("seven_day_opus", "7d Opus", 604_800),
        ("seven_day_sonnet", "7d Sonnet", 604_800),
    ]

    /// Returns known windows in fixed order, then extra windows sorted by key. Throws
    /// ``DecodingFailure`` when the response no longer matches.
    public static func decode(_ data: Data) throws(DecodingFailure) -> [UsageWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DecodingFailure()
        }
        var windows: [UsageWindow] = []
        for entry in known {
            guard let object = root[entry.key] as? [String: Any], !(object["utilization"] is NSNull) else {
                continue
            }
            windows.append(try window(entry.key, entry.label, .seconds(entry.seconds), object))
        }
        let knownKeys = Set(known.map(\.key))
        for key in root.keys.sorted() where !knownKeys.contains(key) {
            guard let object = root[key] as? [String: Any], isWindowShaped(object) else {
                continue
            }
            windows.append(try window(key, key, nil, object))
        }
        return windows
    }

    private static func isWindowShaped(_ object: [String: Any]) -> Bool {
        object.keys.contains("utilization") && object.keys.contains("resets_at") && object["utilization"] is NSNumber
    }

    private static func window(
        _ id: String, _ label: String, _ length: Duration?, _ object: [String: Any]
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
            resetsAt = date
        default:
            throw DecodingFailure()
        }
        return UsageWindow(
            id: id, label: label, usedPercent: utilization.doubleValue, resetsAt: resetsAt, windowLength: length)
    }
}
