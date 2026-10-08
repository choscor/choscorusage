// The real wall clock backed by Date and Task.sleep.
import ChoscorUsageCore
import Foundation

/// The system time.
public struct SystemClock: WallClock {
    /// Creates a clock.
    public init() {}

    /// The current date.
    public var now: Date { Date() }

    /// Sleeps on the continuous clock; throws when cancelled.
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
