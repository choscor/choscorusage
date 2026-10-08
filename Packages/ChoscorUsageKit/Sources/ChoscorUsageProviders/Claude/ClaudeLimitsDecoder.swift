// Decodes the newer `limits[]` array and `extra_usage` object of the Claude usage response.
import ChoscorUsageCore
import Foundation

/// Lenient reader for the parts of `/api/oauth/usage` that replaced the flat `seven_day_*` keys.
///
/// Secondhand shape, not yet seen in a captured response: `limits` entries are
/// `{kind: "session" | "weekly_all" | "weekly_scoped", percent: 0–100, resets_at,
/// scope.model.display_name}`, and the flat `seven_day_*` keys are `null` once `limits` is served
/// (ccusage 0.1.12 notes, https://pypi.org/project/ccusage/, and
/// https://github.com/steipete/CodexBar/blob/main/docs/claude.md, both verified 2026-10-08).
/// `extra_usage` is `{is_enabled, monthly_limit, used_credits, utilization}` with no reset time.
/// Because the shape is unconfirmed, entries that do not fit are skipped instead of failing.
internal enum ClaudeLimitsDecoder {
    private static let week = Duration.seconds(604_800)

    /// Windows from `limits[]` in array order. Known kinds reuse the flat keys' IDs (`five_hour`,
    /// `seven_day`, `seven_day_<model>`) so they replace those windows and keep alert history.
    internal static func limitWindows(in root: [String: Any]) -> [UsageWindow] {
        let entries = root["limits"] as? [Any] ?? []
        return entries.compactMap { ($0 as? [String: Any]).flatMap(window(for:)) }
    }

    /// The `Extra` window when extra usage is enabled and reports a utilization.
    internal static func extraUsageWindow(in root: [String: Any]) -> UsageWindow? {
        guard let extra = root["extra_usage"] as? [String: Any], extra["is_enabled"] as? Bool == true,
            let utilization = extra["utilization"] as? NSNumber
        else {
            return nil
        }
        return UsageWindow(
            id: "extra_usage", label: "Extra", usedPercent: utilization.doubleValue, resetsAt: nil, windowLength: nil)
    }

    private static func window(for entry: [String: Any]) -> UsageWindow? {
        guard let kind = entry["kind"] as? String,
            let percent = (entry["percent"] ?? entry["utilization"]) as? NSNumber
        else {
            return nil
        }
        let identity: (id: String, label: String, length: Duration?)
        switch kind {
        case "session":
            identity = ("five_hour", "5h", .seconds(18_000))
        case "weekly_all":
            identity = ("seven_day", "7d", week)
        case "weekly_scoped":
            guard let model = modelName(in: entry) else {
                return nil
            }
            let slug = model.lowercased().replacingOccurrences(of: " ", with: "_")
            identity = ("seven_day_\(slug)", "7d \(model)", week)
        default:
            identity = ("limits.\(kind)", kind, nil)
        }
        return UsageWindow(
            id: identity.id, label: identity.label, usedPercent: percent.doubleValue,
            resetsAt: resetDate(entry["resets_at"]), windowLength: identity.length)
    }

    private static func modelName(in entry: [String: Any]) -> String? {
        let scope = entry["scope"] as? [String: Any]
        let model = scope?["model"] as? [String: Any]
        return model?["display_name"] as? String
    }

    /// Accepts ISO 8601 text or epoch seconds, since entries may differ from the flat keys.
    private static func resetDate(_ value: Any?) -> Date? {
        switch value {
        case let text as String: ISO8601Timestamp.parse(text)
        case let seconds as NSNumber: Date(timeIntervalSince1970: seconds.doubleValue)
        default: nil
        }
    }
}
