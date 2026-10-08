// The last good set of windows for a profile and where they came from.
import Foundation

/// Where a snapshot's numbers came from.
public enum SnapshotSource: Codable, Equatable, Sendable {
    /// The provider's usage endpoint.
    case endpoint
    /// A Codex session log line recorded at the given time.
    case localLog(recordedAt: Date)
}

/// A successful usage reading for one profile.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    /// Windows in provider order.
    public let windows: [UsageWindow]
    /// When the app obtained this reading.
    public let fetchedAt: Date
    /// Endpoint or local-log origin.
    public let source: SnapshotSource

    /// Creates a snapshot.
    public init(windows: [UsageWindow], fetchedAt: Date, source: SnapshotSource) {
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// When the numbers were true: the log line time for local logs, else the fetch time.
    public var observedAt: Date {
        switch source {
        case .endpoint: fetchedAt
        case .localLog(let recordedAt): recordedAt
        }
    }
}
