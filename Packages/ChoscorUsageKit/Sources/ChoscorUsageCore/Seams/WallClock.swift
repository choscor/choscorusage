// The injectable wall-clock seam (named to avoid shadowing Swift's `Clock`).
import Foundation

/// Supplies the current time and sleeps, so refresh timing is testable.
public protocol WallClock: Sendable {
    /// The current date.
    var now: Date { get }

    /// Suspends for `duration`. Throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}
