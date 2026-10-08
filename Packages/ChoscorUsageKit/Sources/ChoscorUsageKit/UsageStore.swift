// The observable state the app renders, and the actions its views call.
import ChoscorUsageCore
import Foundation
import Observation
import os

/// App-facing state: profiles, their usage, discovery candidates and preferences.
///
/// Main-actor isolated for SwiftUI. Network, Keychain and file work run in ``UsageRefresher``,
/// ``UsagePersistence`` or detached discovery, never on the main actor.
@MainActor
@Observable
public final class UsageStore {
    /// All profiles in user order, including hidden ones.
    public internal(set) var profiles: [Profile] = []
    /// Discovered directories awaiting confirmation.
    public internal(set) var candidates: [DiscoveredProfile] = []
    /// Whether a refresh is running.
    public private(set) var isRefreshing = false
    /// User preferences; changes are saved and applied to the refresh timer immediately.
    public var preferences = UsagePreferences() {
        didSet { preferencesChanged(from: oldValue) }
    }

    private var results: [UUID: ProfileUsage] = [:]
    @ObservationIgnored internal let dependencies: UsageDependencies
    @ObservationIgnored internal let persistence: UsagePersistence
    @ObservationIgnored private var refresher: UsageRefresher
    @ObservationIgnored private var scheduler = RefreshScheduler()
    @ObservationIgnored private var ledger = NotificationLedger()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored internal var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var pendingFetch: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    private static let logger = Logger(subsystem: "com.choscor.ChoscorUsage", category: "store")

    /// Creates a store; call ``start()`` before use.
    public init(dependencies: UsageDependencies) {
        self.dependencies = dependencies
        persistence = UsagePersistence(fileSystem: dependencies.fileSystem)
        refresher = UsageRefresher(
            providers: dependencies.providers, clock: dependencies.clock,
            minimumSpacing: dependencies.minimumFetchSpacing)
    }

    /// Every profile's usage in user order; profiles not yet refreshed are `notLoaded`.
    public var usages: [ProfileUsage] {
        profiles.map { profile in
            let result = results[profile.id]
            return ProfileUsage(profile: profile, state: result?.state ?? .notLoaded, snapshot: result?.snapshot)
        }
    }

    /// Visible profiles' usage, for the menu.
    public var visibleUsages: [ProfileUsage] { usages.filter { !$0.profile.isHidden } }

    /// The menu bar summary with countdowns measured from the clock's current time.
    public var summary: MenuBarSummary { summary(at: dependencies.clock.now) }

    /// The menu bar summary with countdowns measured from `now`, for a label that ticks.
    public func summary(at now: Date) -> MenuBarSummary {
        MenuBarSummary.make(from: usages, chosenProfileID: preferences.chosenProfileID, now: now)
    }

    /// The profile the menu bar shows in full, or `nil` when it shows the worst percentage.
    public var chosenProfileID: UUID? { preferences.chosenProfileID }

    /// Makes `id` the menu bar's profile, or goes back to the worst percentage if it already is.
    /// The choice is saved with the preferences.
    public func toggleChosenProfile(_ id: UUID) {
        preferences.chosenProfileID = preferences.chosenProfileID == id ? nil : id
    }

    /// Restores saved state (showing last good data immediately), runs discovery on first launch,
    /// and performs the launch refresh.
    public func start() async {
        let restored = await persistence.restore()
        isStarted = false
        preferences = dependencies.preferences.load()
        scheduler.interval = preferences.refreshInterval
        profiles = ProfileList(restored.profiles ?? []).profiles
        ledger = restored.ledger
        refresher = UsageRefresher(
            providers: dependencies.providers, clock: dependencies.clock, lastGood: restored.snapshots,
            minimumSpacing: dependencies.minimumFetchSpacing)
        for profile in profiles {
            results[profile.id] = await refresher.usage(for: profile)
        }
        isStarted = true
        if restored.profiles == nil {
            saveProfiles()
            await rescan()
        }
        await refresh(.launch)
    }

    /// Starts the automatic refresh timer; it re-reads the interval every cycle.
    public func startAutomaticRefresh() {
        timer?.cancel()
        let clock = dependencies.clock
        weak let store = self
        timer = Task {
            await RefreshScheduler.runTimer(
                clock: clock,
                interval: { await store?.preferences.refreshInterval ?? .default },
                tick: { await store?.refresh(.timer) }
            )
        }
    }

    /// Stops the automatic refresh timer.
    public func stopAutomaticRefresh() {
        timer?.cancel()
        timer = nil
    }

    /// Refreshes if the scheduler allows `trigger` (manual is debounced to 10 s; menu opens
    /// refresh only data older than 60 s), then delivers notifications and saves results.
    public func refresh(_ trigger: RefreshTrigger) async {
        guard !isRefreshing, scheduler.begin(trigger, now: dependencies.clock.now) else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        record(await refresher.refresh(profiles))
        await finishRefresh()
    }

    /// Clears a Keychain denial for `id` and fetches it now; this is the only path that prompts
    /// again after a denial.
    public func retry(_ id: UUID) async {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            return
        }
        record([await refresher.retry(profile)])
        await finishRefresh()
    }

    /// Waits until queued fetches finish and queued profile writes reach disk.
    public func flush() async {
        await pendingFetch?.value
        await pendingWrite?.value
    }

    /// Fetches newly added or shown profiles now instead of waiting for the next timer tick.
    internal func fetchSoon(_ ids: Set<UUID>) {
        guard isStarted, !ids.isEmpty else {
            return
        }
        let previous = pendingFetch
        weak let store = self
        pendingFetch = Task {
            await previous?.value
            await store?.fetch(ids)
        }
    }

    /// Drops a removed profile's results, last good snapshot and alert history, on disk too.
    internal func discardData(for id: UUID) {
        results[id] = nil
        ledger.forget(profileID: id)
        let remaining = Set(profiles.map(\.id))
        let previous = pendingFetch
        weak let store = self
        pendingFetch = Task {
            await previous?.value
            await store?.refresher.forget(except: remaining)
            await store?.saveResults()
        }
    }

    private func fetch(_ ids: Set<UUID>) async {
        let targets = profiles.filter { ids.contains($0.id) }
        guard !targets.isEmpty else {
            return
        }
        record(await refresher.refresh(targets))
        await finishRefresh()
    }

    private func record(_ fresh: [ProfileUsage]) {
        let current = Set(profiles.map(\.id))
        for usage in fresh where current.contains(usage.profile.id) {
            results[usage.profile.id] = usage
        }
    }

    private func finishRefresh() async {
        let policy = NotificationPolicy(
            thresholdAlertsEnabled: preferences.thresholdAlertsEnabled,
            resetAlertsEnabled: preferences.resetAlertsEnabled)
        let events = policy.evaluate(usages, ledger: &ledger, now: dependencies.clock.now)
        await saveResults()
        if !events.isEmpty {
            await dependencies.notifier.deliver(events)
        }
    }

    private func saveResults() async {
        let snapshots = await refresher.lastGoodSnapshots
        do {
            try await persistence.save(snapshots: snapshots, ledger: ledger)
        } catch {
            Self.logger.error("Saving refresh results failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func preferencesChanged(from old: UsagePreferences) {
        guard isStarted, preferences != old else {
            return
        }
        dependencies.preferences.save(preferences)
        scheduler.interval = preferences.refreshInterval
        if preferences.refreshInterval != old.refreshInterval, timer != nil {
            startAutomaticRefresh()
        }
    }
}
