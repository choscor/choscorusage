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
        self.usedPercent = Self.clamped(usedPercent)
        self.resetsAt = resetsAt
        self.windowLength = windowLength
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, usedPercent, resetsAt, windowLength
    }

    /// Decodes a persisted window, clamping `usedPercent` as ``init(id:label:usedPercent:resetsAt:windowLength:)``
    /// does, so an edited or older file cannot carry an out-of-range percentage into the UI.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            label: try container.decode(String.self, forKey: .label),
            usedPercent: try container.decode(Double.self, forKey: .usedPercent),
            resetsAt: try container.decodeIfPresent(Date.self, forKey: .resetsAt),
            windowLength: try container.decodeIfPresent(Duration.self, forKey: .windowLength))
    }

    private static func clamped(_ percent: Double) -> Double {
        percent.isNaN ? 0 : min(max(percent, 0), 100)
    }
}
