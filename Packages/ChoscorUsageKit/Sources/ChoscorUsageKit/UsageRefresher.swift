// Runs per-profile fetches with bounded concurrency and turns outcomes into profile states.
import ChoscorUsageCore
import Foundation
import os

/// Owns refresh bookkeeping: last good data, 429 backoff, per-provider spacing, and the
/// Keychain-denied gate.
///
/// Runs off the main actor so network, file and Keychain work never blocks the UI.
public actor UsageRefresher {
    private struct Record {
        var state: ProfileState = .notLoaded
        var snapshot: UsageSnapshot?
        var consecutiveRateLimits = 0
        var retryAt: Date?
        var lastFetchedAt: Date?
    }

    private static let maximumConcurrentFetches = 4
    private static let logger = Logger(subsystem: "com.choscor.ChoscorUsage", category: "refresh")

    private let providers: [Provider: any UsageProviding]
    private let clock: any WallClock
    private let minimumSpacing: [Provider: Duration]
    private var records: [UUID: Record] = [:]
    private var inFlight: Set<UUID> = []
    private var queuedRetries: [UUID: Profile] = [:]
    /// Removed profiles whose fetch was still running; their results are discarded.
    private var forgotten: Set<UUID> = []

    /// Creates a refresher seeded with persisted last good snapshots. `minimumSpacing` is the
    /// shortest time between two fetches of one profile per provider (see ``FetchSpacing``).
    public init(
        providers: [Provider: any UsageProviding], clock: any WallClock, lastGood: [UUID: UsageSnapshot] = [:],
        minimumSpacing: [Provider: Duration] = [:]
    ) {
        self.providers = providers
        self.clock = clock
        self.minimumSpacing = minimumSpacing
        records = lastGood.mapValues { Record(snapshot: $0) }
    }

    /// The most recent successful snapshot per profile, for persistence.
    public var lastGoodSnapshots: [UUID: UsageSnapshot] {
        records.compactMapValues(\.snapshot)
    }

    /// Returns the current usage for `profile` without fetching.
    public func usage(for profile: Profile) -> ProfileUsage {
        let record = records[profile.id] ?? Record()
        return ProfileUsage(profile: profile, state: record.state, snapshot: record.snapshot)
    }

    /// Refreshes visible profiles, at most four at once. Skips profiles waiting out a 429
    /// backoff, profiles fetched within their provider's minimum spacing, and profiles whose
    /// Keychain access was denied (only ``retry(_:)`` prompts again, and it ignores spacing).
    /// Returns the usage of every given profile in input order.
    public func refresh(_ profiles: [Profile]) async -> [ProfileUsage] {
        let now = clock.now
        let due = profiles.filter { profile in
            let record = records[profile.id] ?? Record()
            return !profile.isHidden && record.state != .keychainDenied && (record.retryAt.map { now >= $0 } ?? true)
                && isSpacedOut(record, provider: profile.provider, now: now)
        }
        await fetch(due)
        return profiles.map(usage(for:))
    }

    private func isSpacedOut(_ record: Record, provider: Provider, now: Date) -> Bool {
        guard let last = record.lastFetchedAt, let spacing = minimumSpacing[provider] else {
            return true
        }
        return now.timeIntervalSince(last) >= TimeInterval(spacing.components.seconds)
    }

    /// Clears a Keychain denial and fetches `profile` immediately, which may prompt again. While
    /// a fetch for `profile` is running, the retry is queued to run (with this `profile` value,
    /// e.g. a newly picked Keychain item) as soon as that fetch ends, and the current usage is
    /// returned; the running fetch's caller receives the retried result.
    public func retry(_ profile: Profile) async -> ProfileUsage {
        guard !inFlight.contains(profile.id) else {
            queuedRetries[profile.id] = profile
            return usage(for: profile)
        }
        clearBackoffAndDenial(profile.id)
        await fetch([profile])
        return usage(for: profile)
    }

    /// Drops bookkeeping for profiles that no longer exist; results of fetches still running
    /// for them are discarded.
    public func forget(except ids: Set<UUID>) {
        records = records.filter { ids.contains($0.key) }
        queuedRetries = queuedRetries.filter { ids.contains($0.key) }
        forgotten = inFlight.subtracting(ids)
    }

    private func clearBackoffAndDenial(_ id: UUID) {
        records[id, default: Record()].state = .notLoaded
        records[id]?.retryAt = nil
    }

    /// Fetches `profiles`, skipping any already in flight so a profile is never fetched twice
    /// at once (which could also stack Keychain prompts), then runs retries queued meanwhile.
    private func fetch(_ requested: [Profile]) async {
        let profiles = requested.filter { !inFlight.contains($0.id) }
        inFlight.formUnion(profiles.map(\.id))
        await fetchConcurrently(profiles)
        inFlight.subtract(profiles.map(\.id))
        forgotten.subtract(profiles.map(\.id))
        let retries = profiles.compactMap { queuedRetries.removeValue(forKey: $0.id) }
        guard !retries.isEmpty else {
            return
        }
        retries.forEach { clearBackoffAndDenial($0.id) }
        await fetch(retries)
    }

    private func fetchConcurrently(_ profiles: [Profile]) async {
        let providers = providers
        await withTaskGroup(of: (UUID, UsageFetchOutcome).self) { group in
            var pending = profiles[...]
            func startNext() {
                while let profile = pending.popFirst() {
                    guard let provider = providers[profile.provider] else {
                        apply(
                            .failed(detail: "\(profile.provider.displayName) isn't supported", fallback: nil),
                            to: profile)
                        continue
                    }
                    group.addTask { (profile.id, await provider.fetch(profile)) }
                    return
                }
            }
            for _ in 0..<Self.maximumConcurrentFetches {
                startNext()
            }
            for await (id, outcome) in group {
                if let profile = profiles.first(where: { $0.id == id }) {
                    apply(outcome, to: profile)
                }
                startNext()
            }
        }
    }

    private func apply(_ outcome: UsageFetchOutcome, to profile: Profile) {
        guard !forgotten.contains(profile.id) else {
            return
        }
        var record = records[profile.id] ?? Record()
        let now = clock.now
        record.lastFetchedAt = now
        if outcome != .rateLimited {
            record.consecutiveRateLimits = 0
            record.retryAt = nil
        }
        switch outcome {
        case .success(let snapshot):
            record.state = .fresh
            record.snapshot = snapshot
        case .rateLimited:
            record.consecutiveRateLimits += 1
            let delay = RateLimitBackoff.delay(afterConsecutiveRateLimits: record.consecutiveRateLimits)
            let retryAt = now.addingTimeInterval(TimeInterval(delay.components.seconds))
            record.retryAt = retryAt
            record.state = .rateLimited(retryAt: retryAt)
        case .failed(let detail, let fallback):
            record.state = .error(detail: detail)
            record.snapshot = Self.newer(fallback, than: record.snapshot)
        case .unsupportedResponse(let fallback):
            record.state = .unsupportedResponse
            record.snapshot = Self.newer(fallback, than: record.snapshot)
        default:
            record.state = Self.state(for: outcome, provider: profile.provider)
        }
        Self.logger.info("Refreshed profile \(profile.id, privacy: .private): \(String(describing: record.state.kind))")
        records[profile.id] = record
    }

    private static func state(for outcome: UsageFetchOutcome, provider: Provider) -> ProfileState {
        switch outcome {
        case .stale: .stale(provider)
        case .keychainDenied: .keychainDenied
        case .keychainItemNotFound: .keychainItemNotFound
        case .credentialsNotFound: .credentialsNotFound
        case .apiKeyMode: .apiKeyMode
        default: .error(detail: "Unexpected refresh result")
        }
    }

    private static func newer(_ fallback: UsageSnapshot?, than current: UsageSnapshot?) -> UsageSnapshot? {
        guard let fallback else {
            return current
        }
        guard let current else {
            return fallback
        }
        return fallback.observedAt > current.observedAt ? fallback : current
    }
}
