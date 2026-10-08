// Exponential backoff after HTTP 429 responses, capped at 30 minutes.

/// How long to wait before retrying a profile the provider rate-limited.
public enum RateLimitBackoff {
    private static let base = 60
    private static let maximum = 30 * 60

    /// Returns 1 minute after the first 429, doubling per consecutive 429, capped at 30 minutes.
    public static func delay(afterConsecutiveRateLimits count: Int) -> Duration {
        let exponent = min(max(count - 1, 0), 16)
        return .seconds(min(base << exponent, maximum))
    }
}
