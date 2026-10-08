// Tests the app-facing store: discovery confirmation, persistence, notifications and summary.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Synchronization
import Testing

@testable import ChoscorUsageKit

@MainActor
struct UsageStoreTests {
    private let home: TemporaryHome
    private let clock = FakeClock()
    private let provider = ScriptedProvider()
    private let notifier = RecordingNotifier()
    private let defaults: UserDefaults

    init() throws {
        home = try TemporaryHome()
        let suite = "ChoscorUsageTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func launch(provider: any UsageProviding) async -> UsageStore {
        let dependencies = UsageDependencies(
            fileSystem: LocalFileSystem(homeDirectory: home.path), keychain: FakeKeychain(),
            environment: FakeEnvironment(), clock: clock, providers: [.claude: provider, .codex: provider],
            notifier: notifier, preferences: PreferencesStore(defaults: defaults))
        let store = UsageStore(dependencies: dependencies)
        await store.start()
        return store
    }

    private func launch() async -> UsageStore {
        await launch(provider: provider)
    }

    private func window(_ percent: Double) -> UsageSnapshot {
        let window = UsageWindow(
            id: "five_hour", label: "5h", usedPercent: percent, resetsAt: clock.now.addingTimeInterval(3_600),
            windowLength: .seconds(18_000))
        return UsageSnapshot(windows: [window], fetchedAt: clock.now, source: .endpoint)
    }

    @Test func firstLaunchOffersCandidatesAndAddsOnlyConfirmedOnes() async throws {
        try home.write(".claude-03/.credentials.json", "{}")
        try home.makeDirectory(".codex")
        let store = await launch()
        #expect(store.profiles.isEmpty)
        #expect(store.candidates.map(\.displayName) == ["Claude · 03", "Codex"])
        store.add(Array(store.candidates.prefix(1)))
        #expect(store.profiles.map(\.displayName) == ["Claude · 03"])
        #expect(store.candidates.map(\.displayName) == ["Codex"], "unconfirmed candidates stay pending")
        store.dismissCandidates()
        await store.flush()
        let relaunched = await launch()
        #expect(relaunched.profiles.map(\.displayName) == ["Claude · 03"])
        #expect(relaunched.candidates.isEmpty, "discovery runs automatically only on first launch")
        await relaunched.rescan()
        #expect(relaunched.candidates.map(\.displayName) == ["Codex"])
    }

    @Test func profileEditsPersistAcrossLaunches() async throws {
        let store = await launch()
        for name in ["a", "b", "c"] {
            store.addProfile(provider: .claude, directory: "\(home.path)/.claude-\(name)")
        }
        let ids = store.profiles.map(\.id)
        try #require(ids.count == 3)
        store.rename(ids[0], to: "Work")
        store.setHidden(ids[1], true)
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        store.remove(ids[1])
        await store.flush()
        let relaunched = await launch()
        #expect(relaunched.profiles.map(\.displayName) == ["Claude · c", "Work"])
        #expect(relaunched.profiles.map(\.order) == [0, 1])
        let path = "\(home.path)/Library/Application Support/com.choscor.ChoscorUsage/profiles.json"
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func removingAProfileWhileARefreshIsRunningStillDeletesItsSavedUsage() async throws {
        let gate = GatedProvider(outcome: .success(window(85)))
        gate.open()
        let store = await launch(provider: gate)
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-a")
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-b")
        await store.flush()
        let ids = store.profiles.map(\.id)
        try #require(ids.count == 2)
        gate.close()
        clock.advance(by: .seconds(30))
        let fetchedBefore = gate.started
        async let refreshed: Void = store.refresh(.manual)
        await gate.waitUntilStarted(fetchedBefore + 2)
        store.remove(ids[0])
        await store.flush()
        gate.open()
        await refreshed
        await store.flush()
        let directory = "\(home.path)/Library/Application Support/com.choscor.ChoscorUsage"
        let text = try String(contentsOfFile: "\(directory)/snapshots.json", encoding: .utf8)
        #expect(!text.contains(ids[0].uuidString))
        #expect(text.contains(ids[1].uuidString))
    }

    @Test func movingSeveralProfilesToTheEndKeepsTheirRelativeOrder() async {
        let store = await launch()
        for name in ["a", "b", "c", "d"] {
            store.addProfile(provider: .claude, directory: "\(home.path)/.claude-\(name)")
        }
        store.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        #expect(store.profiles.map(\.displayName) == ["Claude · b", "Claude · d", "Claude · a", "Claude · c"])
        #expect(store.profiles.map(\.order) == [0, 1, 2, 3])
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        #expect(store.profiles.map(\.displayName) == ["Claude · b", "Claude · c", "Claude · d", "Claude · a"])
    }

    @Test func notificationsAreDeliveredOnceEvenAcrossARelaunch() async throws {
        let store = await launch()
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-work")
        provider.outcome = .success(window(85))
        clock.advance(by: .seconds(30))
        await store.refresh(.manual)
        #expect(notifier.bodies == ["5h window at 85%"])
        await store.flush()
        let relaunched = await launch()
        #expect(relaunched.usages.first?.state == .fresh)
        #expect(notifier.bodies == ["5h window at 85%"])
    }

    @Test func lastGoodDataIsShownAfterRelaunchEvenWhenTheFirstFetchFails() async throws {
        let store = await launch()
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-work")
        provider.outcome = .success(window(64))
        clock.advance(by: .seconds(30))
        await store.refresh(.manual)
        provider.outcome = .failed(detail: "Couldn't reach Claude", fallback: nil)
        await store.flush()
        let relaunched = await launch()
        let usage = try #require(relaunched.usages.first)
        #expect(usage.state == .error(detail: "Couldn't reach Claude"))
        #expect(usage.snapshot?.windows.first?.usedPercent == 64)
        #expect(relaunched.summary.text == "64%")
    }

    @Test func preferencesDefaultToFiveMinutesAndPersist() async {
        let store = await launch()
        #expect(store.preferences == UsagePreferences(refreshInterval: .fiveMinutes))
        store.preferences.refreshInterval = .tenMinutes
        store.preferences.resetAlertsEnabled = false
        await store.flush()
        let relaunched = await launch()
        #expect(relaunched.preferences.refreshInterval == .tenMinutes)
        #expect(!relaunched.preferences.resetAlertsEnabled)
    }

    @Test func manualRefreshIsDebounced() async {
        let store = await launch()
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-work")
        await store.flush()
        let afterAdd = provider.fetchCount
        clock.advance(by: .seconds(30))
        await store.refresh(.manual)
        await store.refresh(.manual)
        #expect(provider.fetchCount == afterAdd + 1)
    }

    @Test func addedAndUnhiddenProfilesAreFetchedWithoutWaitingForTheTimer() async throws {
        provider.outcome = .success(window(40))
        let store = await launch()
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-work")
        await store.flush()
        #expect(store.usages.map(\.state) == [.fresh])
        let id = try #require(store.profiles.first?.id)
        store.setHidden(id, true)
        await store.flush()
        let whileHidden = provider.fetchCount
        store.setHidden(id, false)
        await store.flush()
        #expect(provider.fetchCount == whileHidden + 1)
    }

    @Test func removingAProfileDeletesItsSavedUsageAndAlertHistory() async throws {
        let store = await launch()
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-a")
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-b")
        provider.outcome = .success(window(85))
        clock.advance(by: .seconds(30))
        await store.refresh(.manual)
        let ids = store.profiles.map(\.id)
        try #require(ids.count == 2)
        store.remove(ids[0])
        await store.flush()
        let directory = "\(home.path)/Library/Application Support/com.choscor.ChoscorUsage"
        for file in ["snapshots.json", "notification-ledger.json"] {
            let text = try String(contentsOfFile: "\(directory)/\(file)", encoding: .utf8)
            #expect(!text.contains(ids[0].uuidString), "\(file) still mentions the removed profile")
            #expect(text.contains(ids[1].uuidString), "\(file) lost the remaining profile")
        }
    }
}

/// Returns one scripted outcome for every profile.
private final class ScriptedProvider: UsageProviding {
    private let state = Mutex<(outcome: UsageFetchOutcome, count: Int)>((.apiKeyMode, 0))

    var outcome: UsageFetchOutcome {
        get { state.withLock { $0.outcome } }
        set { state.withLock { $0.outcome = newValue } }
    }

    var fetchCount: Int { state.withLock { $0.count } }

    func fetch(_: Profile) async -> UsageFetchOutcome {
        state.withLock { state in
            state.count += 1
            return state.outcome
        }
    }
}

/// Records delivered notification bodies.
private final class RecordingNotifier: UsageNotifying {
    private let delivered = Mutex<[String]>([])

    var bodies: [String] { delivered.withLock { $0 } }

    func deliver(_ notifications: [UsageNotification]) async {
        delivered.withLock { $0 += notifications.map(\.body) }
    }
}
