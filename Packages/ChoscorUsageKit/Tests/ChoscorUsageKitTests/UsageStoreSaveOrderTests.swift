// Tests that overlapping refresh saves reach disk in the order they started.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Synchronization
import Testing

@testable import ChoscorUsageKit

@MainActor
struct UsageStoreSaveOrderTests {
    private let home: TemporaryHome
    private let defaults: UserDefaults
    private let clock = FakeClock()

    init() throws {
        home = try TemporaryHome()
        let suite = "ChoscorUsageSaveOrderTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func snapshot(_ percent: Double) -> UsageFetchOutcome {
        let window = UsageWindow(id: "five_hour", label: "5h", usedPercent: percent, resetsAt: nil, windowLength: nil)
        return .success(UsageSnapshot(windows: [window], fetchedAt: clock.now, source: .endpoint))
    }

    private func savedPercent() throws -> Double? {
        let path = "\(UsagePersistence.directory(home: home.path))/snapshots.json"
        let data = try Data(contentsOf: URL(filePath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([UUID: UsageSnapshot].self, from: data).values.first?.windows.first?.usedPercent
    }

    private func percent(in store: UsageStore) -> Double? {
        store.usages.first?.snapshot?.windows.first?.usedPercent
    }

    /// Waits until the store shows `percent`, then briefly longer so that refresh's save reaches
    /// the busy persistence actor. Saves give no signal when they are queued, so only the
    /// pre-fix failure depends on this pause; the fixed ordering holds however long it is.
    private func settle(at percent: Double, in store: UsageStore) async throws {
        while self.percent(in: store) != percent {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test(.timeLimit(.minutes(1)))
    func aRetryThatOverlapsARefreshSavesTheNewerResultLast() async throws {
        let files = BlockingFileSystem(homeDirectory: home.path)
        let provider = SwitchableProvider()
        let store = UsageStore(
            dependencies: UsageDependencies(
                fileSystem: files, keychain: FakeKeychain(), environment: FakeEnvironment(), clock: clock,
                providers: [.claude: provider], notifier: QuietNotifier(),
                preferences: PreferencesStore(defaults: defaults)))
        await store.start()
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-a")
        await store.flush()
        let id = try #require(store.profiles.first?.id)

        files.block(fileName: "profiles.json")
        store.rename(id, to: "Busy")
        await files.waitUntilBlocked()
        provider.outcome = snapshot(10)
        clock.advance(by: .seconds(30))
        let older = Task(priority: .background) { await store.refresh(.manual) }
        try await settle(at: 10, in: store)
        provider.outcome = snapshot(20)
        let newer = Task(priority: .high) { await store.retry(id) }
        try await settle(at: 20, in: store)
        files.unblock()
        await older.value
        await newer.value
        await store.flush()
        #expect(try savedPercent() == 20)
    }
}

/// Returns whatever outcome the test last set.
private final class SwitchableProvider: UsageProviding {
    private let state = Mutex<UsageFetchOutcome>(.apiKeyMode)

    var outcome: UsageFetchOutcome {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    func fetch(_: Profile, allowingPrompt _: Bool) async -> UsageFetchOutcome { outcome }
}

private struct QuietNotifier: UsageNotifying {
    func deliver(_: [UsageNotification]) async {}
}
