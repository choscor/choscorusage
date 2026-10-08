// The provider-neutral usage window every decoder produces.
import Foundation

/// One rate-limit window for a profile, normalized across providers.
public struct UsageWindow: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Stable identifier within a profile, such as `five_hour` or `primary_window`.
    public let id: String
    /// Short display label derived from the window length, such as `5h` or `7d Opus`.
    public let label: String
    /// Percentage of the window used, clamped to 0...100.
    public let usedPercent: Double
    /// When the window resets, if the provider reported it.
    public let resetsAt: Date?
    /// The window length, if known.
    public let windowLength: Duration?

    /// Creates a window; `usedPercent` is clamped to 0...100.
    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?, windowLength: Duration?) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent.isNaN ? 0 : min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
        self.windowLength = windowLength
    }
}
