// Manually advanced WallClock fake; sleeping advances time instantly.
import ChoscorUsageCore
import Foundation
import Synchronization

/// A clock whose time moves only when a test advances it or something sleeps.
public final class FakeClock: WallClock {
    private let state: Mutex<(now: Date, sleeps: [Duration])>

    /// Creates a clock at `now`.
    public init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        state = Mutex((now, []))
    }

    /// The current fake time.
    public var now: Date { state.withLock { $0.now } }

    /// Durations passed to `sleep(for:)`, in order.
    public var sleeps: [Duration] { state.withLock { $0.sleeps } }

    /// Moves time forward.
    public func advance(by duration: Duration) {
        state.withLock { $0.now = $0.now.addingTimeInterval(duration.timeInterval) }
    }

    /// Records the sleep and advances time by `duration` without waiting.
    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.sleeps.append(duration)
            state.now = state.now.addingTimeInterval(duration.timeInterval)
        }
        await Task.yield()
    }
}

extension Duration {
    /// The duration in seconds as a `TimeInterval`.
    public var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
