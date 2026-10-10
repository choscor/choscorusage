// A WallClock whose sleeps never finish on their own, only when their task is cancelled.
import ChoscorUsageCore
import Foundation
import Synchronization

/// Lets a test see whether a timer loop is still waiting or was cancelled.
final class ParkedClock: WallClock {
    private struct State {
        var parked: [UUID: CheckedContinuation<Void, Never>] = [:]
        var cancelledBeforeParking: Set<UUID> = []
        var parkedCount = 0
        var cancelledCount = 0
        var parkWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Sleeps cut short by cancellation so far.
    var cancelledSleeps: Int { state.withLock { $0.cancelledCount } }

    /// Returns once some sleep has started.
    func waitUntilParked() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                guard state.parkedCount == 0 else {
                    return true
                }
                state.parkWaiters.append(continuation)
                return false
            }
            if ready {
                continuation.resume()
            }
        }
    }

    func sleep(for _: Duration) async throws {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let (cancelled, waiters) = state.withLock { state in
                    if state.cancelledBeforeParking.remove(id) != nil {
                        return (true, [CheckedContinuation<Void, Never>]())
                    }
                    state.parked[id] = continuation
                    state.parkedCount += 1
                    defer { state.parkWaiters = [] }
                    return (false, state.parkWaiters)
                }
                waiters.forEach { $0.resume() }
                if cancelled {
                    continuation.resume()
                }
            }
        } onCancel: {
            let continuation = state.withLock { state in
                state.cancelledCount += 1
                guard let continuation = state.parked.removeValue(forKey: id) else {
                    state.cancelledBeforeParking.insert(id)
                    return CheckedContinuation<Void, Never>?.none
                }
                return continuation
            }
            continuation?.resume()
        }
        try Task.checkCancellation()
    }
}
