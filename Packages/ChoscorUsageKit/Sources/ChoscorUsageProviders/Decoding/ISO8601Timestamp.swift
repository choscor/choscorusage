// Parses the ISO 8601 timestamps the providers emit, with or without fractional seconds.
import Foundation

/// Lenient ISO 8601 parsing for provider timestamps.
internal enum ISO8601Timestamp {
    /// Parses `text` such as `2026-10-08T15:59:59.943648+00:00` or `2026-10-08T15:00:00Z`.
    /// Fractions are truncated to whole seconds, which is all reset times need.
    internal static func parse(_ text: String) -> Date? {
        let wholeSeconds = text.replacing(/\.\d+/, with: "", maxReplacements: 1)
        return try? Date(wholeSeconds, strategy: .iso8601)
    }
}
