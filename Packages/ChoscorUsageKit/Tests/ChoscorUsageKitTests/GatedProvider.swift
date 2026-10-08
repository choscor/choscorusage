// A provider whose fetches block until the test opens a gate, for deterministic overlap tests.
import ChoscorUsageCore
import Synchronization

/// Fetches start immediately but return only once ``open()`` is called; counts starts and overlap.
final class GatedProvider: UsageProviding {
    private struct State {
        var outcome: UsageFetchOutcome
        var isOpen = false
        var started = 0
        var running = 0
        var peak = 0
        var gate: [CheckedContinuation<Void, Never>] = []
        var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state: Mutex<State>

    init(outcome: UsageFetchOutcome) {
        state = Mutex(State(outcome: outcome))
    }

    var started: Int { state.withLock { $0.started } }
    var peak: Int { state.withLock { $0.peak } }

    func open() {
        let waiting = state.withLock { state in
            state.isOpen = true
            defer { state.gate = [] }
            return state.gate
        }
        waiting.forEach { $0.resume() }
    }

    func close() {
        state.withLock { $0.isOpen = false }
    }

    /// Returns once at least `count` fetches have started in total.
    func waitUntilStarted(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let done = state.withLock { state in
                guard state.started < count else {
                    return true
                }
                state.startWaiters.append((count, continuation))
                return false
            }
            if done {
                continuation.resume()
            }
        }
    }

    func fetch(_: Profile) async -> UsageFetchOutcome {
        let due = state.withLock { state in
            state.started += 1
            state.running += 1
            state.peak = max(state.peak, state.running)
            let due = state.startWaiters.filter { $0.count <= state.started }
            state.startWaiters.removeAll { $0.count <= state.started }
            return due.map(\.continuation)
        }
        due.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            let pass = state.withLock { state in
                guard !state.isOpen else {
                    return true
                }
                state.gate.append(continuation)
                return false
            }
            if pass {
                continuation.resume()
            }
        }
        return state.withLock { state in
            state.running -= 1
            return state.outcome
        }
    }
}
