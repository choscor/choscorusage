// Decodes the private Codex usage response into normalized windows.
import ChoscorUsageCore
import Foundation

/// Decoder for `GET <chatgpt_base_url>/wham/usage`.
///
/// Private and undocumented by OpenAI; shape from CodexBar's `CodexUsageResponse`
/// (https://github.com/steipete/CodexBar/blob/main/docs/codex.md, verified 2026-10-08).
/// `rate_limit.primary_window`/`secondary_window` and each `additional_rate_limits[].rate_limit`
/// hold `{used_percent, limit_window_seconds, reset_after_seconds, reset_at}`. Plans differ, so
/// labels come from `limit_window_seconds`, never from a fixed 5h/7d assumption.
public enum CodexUsageDecoder {
    /// The body no longer matches the expected shape.
    public struct DecodingFailure: Error, Equatable {}

    private struct Response: Decodable {
        let rateLimit: RateLimit?
        let additionalRateLimits: [Additional]?
    }

    private struct Additional: Decodable {
        let limitName: String?
        let rateLimit: RateLimit?
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAfterSeconds: Int?
        let resetAt: Int?
    }

    /// Returns primary and secondary windows, then each additional limit's windows labelled
    /// with its name. `now` resolves `reset_after_seconds` when `reset_at` is absent.
    public static func decode(_ data: Data, now: Date) throws(DecodingFailure) -> [UsageWindow] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data) else {
            throw DecodingFailure()
        }
        var windows = windows(of: response.rateLimit, prefix: nil, now: now)
        for (index, additional) in (response.additionalRateLimits ?? []).enumerated() {
            let name = additional.limitName ?? "Limit \(index + 1)"
            windows += Self.windows(of: additional.rateLimit, prefix: name, now: now)
        }
        return windows
    }

    private static func windows(of rateLimit: RateLimit?, prefix: String?, now: Date) -> [UsageWindow] {
        let slots = [("primary_window", rateLimit?.primaryWindow), ("secondary_window", rateLimit?.secondaryWindow)]
        return slots.compactMap { id, window in
            guard let window else {
                return nil
            }
            let length = window.limitWindowSeconds
            let label = length.map { WindowLabel.short(forSeconds: $0) } ?? id
            let resetsAt =
                window.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ?? window.resetAfterSeconds.map { now.addingTimeInterval(TimeInterval($0)) }
            return UsageWindow(
                id: prefix.map { "\($0).\(id)" } ?? id,
                label: prefix.map { "\($0) \(label)" } ?? label,
                usedPercent: window.usedPercent,
                resetsAt: resetsAt,
                windowLength: length.map { .seconds($0) })
        }
    }
}
