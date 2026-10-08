// Maps non-success HTTP statuses to fetch outcomes the same way for every provider.
import ChoscorUsageCore

/// Shared status handling: 401/403 stale, 429 rate limited, anything else a failure.
internal enum HTTPStatusOutcome {
    /// Returns the outcome for a non-2xx `status` from `providerName`.
    internal static func outcome(forStatus status: Int, providerName: String) -> UsageFetchOutcome {
        switch status {
        case 401, 403: .stale
        case 429: .rateLimited
        default: .failed(detail: "\(providerName) returned HTTP \(status)", fallback: nil)
        }
    }
}
