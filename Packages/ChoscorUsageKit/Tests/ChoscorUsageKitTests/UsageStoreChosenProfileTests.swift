// Tests choosing the profile whose menu badge the menu bar shows, and that the choice persists.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageKit

@MainActor
struct UsageStoreChosenProfileTests {
    private let home: TemporaryHome
    private let defaults: UserDefaults

    init() throws {
        home = try TemporaryHome()
        let suite = "ChoscorUsageChosenTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func launch() async -> UsageStore {
        let dependencies = UsageDependencies(
            fileSystem: LocalFileSystem(homeDirectory: home.path), keychain: FakeKeychain(),
            environment: FakeEnvironment(), clock: FakeClock(),
            providers: [.claude: APIKeyProvider(), .codex: APIKeyProvider()],
            notifier: SilentNotifier(), preferences: PreferencesStore(defaults: defaults))
        let store = UsageStore(dependencies: dependencies)
        await store.start()
        store.dismissCandidates()
        return store
    }

    private func launchWithTwoProfiles() async throws -> (UsageStore, [UUID]) {
        let store = await launch()
        store.addProfile(provider: .claude, directory: "\(home.path)/.claude-a")
        store.addProfile(provider: .codex, directory: "\(home.path)/.codex-b")
        await store.flush()
        let ids = store.profiles.map(\.id)
        try #require(ids.count == 2)
        return (store, ids)
    }

    @Test func choosingAProfileShowsItsBadgeAndChoosingItAgainClearsIt() async throws {
        let (store, ids) = try await launchWithTwoProfiles()
        #expect(store.summary.text == "—")

        store.toggleChosenProfile(ids[1])
        #expect(store.chosenProfileID == ids[1])
        #expect(store.summary.text == "API key mode")

        store.toggleChosenProfile(ids[1])
        #expect(store.chosenProfileID == nil)
        #expect(store.summary.text == "—")
    }

    @Test func theChoiceSurvivesARelaunchUntilTheProfileIsRemoved() async throws {
        let (store, ids) = try await launchWithTwoProfiles()
        store.toggleChosenProfile(ids[0])
        await store.flush()

        let relaunched = await launch()
        #expect(relaunched.chosenProfileID == ids[0])
        relaunched.remove(ids[0])
        #expect(relaunched.chosenProfileID == nil)
        await relaunched.flush()
        #expect(await launch().chosenProfileID == nil)
    }
}

/// Every fetch reports API-key mode, so nothing touches the network.
private struct APIKeyProvider: UsageProviding {
    func fetch(_: Profile, allowingPrompt _: Bool) async -> UsageFetchOutcome { .apiKeyMode }
}

/// Drops notifications.
private struct SilentNotifier: UsageNotifying {
    func deliver(_: [UsageNotification]) async {}
}
