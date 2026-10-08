// Decides when a refresh runs: interval timer, debounced manual refresh, menu opens and wake.
import ChoscorUsageCore
import Foundation

/// Refresh timing rules. Value type; the store owns one and consults it for every trigger.
public struct RefreshScheduler: Sendable {
    private static let manualDebounce: TimeInterval = 10
    private static let menuStaleness: TimeInterval = 60

    /// The automatic interval; 5 minutes unless the user picks 1, 2 or 10.
    public var interval: RefreshInterval = .default
    private var lastRefresh: Date?

    /// Creates a scheduler with the default interval.
    public init() {}

    /// Returns whether `trigger` should refresh now, and records the refresh if so. Manual
    /// refreshes run at most once per 10 s; menu opens refresh only data older than 60 s;
    /// launch, timer, wake and retry always refresh.
    public mutating func begin(_ trigger: RefreshTrigger, now: Date) -> Bool {
        let age = lastRefresh.map { now.timeIntervalSince($0) } ?? .infinity
        let allowed: Bool
        switch trigger {
        case .manual: allowed = age >= Self.manualDebounce
        case .menuOpened: allowed = age > Self.menuStaleness
        case .launch, .timer, .wake, .retry: allowed = true
        }
        if allowed {
            lastRefresh = now
        }
        return allowed
    }

    /// Sleeps one interval (re-read each cycle, so Settings changes apply) and calls `tick`, until
    /// the calling task is cancelled.
    public static func runTimer(
        clock: any WallClock, interval: @escaping @Sendable () async -> RefreshInterval,
        tick: @Sendable () async -> Void
    ) async {
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: await interval().duration)
            } catch {
                return
            }
            await tick()
        }
    }
}
