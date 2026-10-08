// Tests adding a picked folder as a profile, with the provider detected from its contents.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageKit

@MainActor
struct UsageStoreAddProfileTests {
    private let home: TemporaryHome
    private let defaults: UserDefaults

    init() throws {
        home = try TemporaryHome()
        let suite = "ChoscorUsageAddTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func launch() async throws -> UsageStore {
        let dependencies = UsageDependencies(
            fileSystem: LocalFileSystem(homeDirectory: home.path), keychain: FakeKeychain(),
            environment: FakeEnvironment(), clock: FakeClock(),
            providers: [.claude: APIKeyProvider(), .codex: APIKeyProvider()],
            notifier: SilentNotifier(), preferences: PreferencesStore(defaults: defaults))
        let store = UsageStore(dependencies: dependencies)
        await store.start()
        // The first-launch scan offers the test folders; these tests add them by hand instead.
        store.dismissCandidates()
        return store
    }

    @Test func detectsTheProviderFromTheFolderContents() async throws {
        try home.write("work-claude-cfg/settings.json", "{}")
        try home.write("team/auth.json", "{}")
        let store = try await launch()

        let claude = await store.addProfile(directory: "\(home.path)/work-claude-cfg")
        let codex = await store.addProfile(directory: "\(home.path)/team")

        #expect(store.profiles.map(\.provider) == [.claude, .codex])
        #expect(store.profiles.map(\.displayName) == ["Claude · work-claude-cfg", "Codex · team"])
        #expect([claude, codex] == store.profiles.map { .added($0) })
    }

    @Test func fallsBackToTheFolderNameWhenItHasNoMarkerFiles() async throws {
        try home.makeDirectory(".codex-new")
        let store = try await launch()

        _ = await store.addProfile(directory: "\(home.path)/.codex-new")

        #expect(store.profiles.map(\.provider) == [.codex])
    }

    @Test func rejectsAFolderThatIsNeitherClaudeNorCodex() async throws {
        try home.write("Documents/notes.txt", "")
        let store = try await launch()

        #expect(await store.addProfile(directory: "\(home.path)/Documents") == .unrecognized)
        #expect(store.profiles.isEmpty)
    }

    @Test func doesNotAddTheSameFolderTwice() async throws {
        try home.write(".claude-work/.credentials.json", "{}")
        let store = try await launch()
        _ = await store.addProfile(directory: "\(home.path)/.claude-work")

        let again = await store.addProfile(directory: "\(home.path)/.claude-work/")

        #expect(store.profiles.count == 1)
        #expect(again == store.profiles.first.map { .alreadyAdded($0) })
    }

    @Test func addingAScannedFolderByHandRemovesItsPendingCandidate() async throws {
        try home.write(".claude-work/.credentials.json", "{}")
        let store = try await launch()
        await store.rescan()
        let pending = store.candidates

        _ = await store.addProfile(directory: "\(home.path)/.claude-work")
        #expect(store.candidates.isEmpty)
        store.add(pending)

        #expect(store.profiles.count == 1, "confirming a stale candidate must not add the folder twice")
    }

    @Test func dismissingRemovesOnlyTheCandidatesThatWereShown() async throws {
        try home.write(".claude-work/.credentials.json", "{}")
        try home.write(".codex/auth.json", "{}")
        let store = try await launch()
        await store.rescan()
        let shown = Array(store.candidates.prefix(1))

        store.dismiss(shown)

        #expect(store.candidates.map(\.displayName) == ["Codex"])
    }

    @Test func rejectsTheHomeFolderEvenWithAProjectsFolderInIt() async throws {
        try home.makeDirectory("projects")
        let store = try await launch()

        #expect(await store.addProfile(directory: home.path) == .unrecognized)
    }

    @Test func aCredentialFileOutweighsAGenericMarkerFolder() async throws {
        try home.write("cfg/auth.json", "{}")
        try home.makeDirectory("cfg/projects")
        let store = try await launch()

        _ = await store.addProfile(directory: "\(home.path)/cfg")

        #expect(store.profiles.map(\.provider) == [.codex])
    }
}

/// Every fetch reports API-key mode, so nothing touches the network.
private struct APIKeyProvider: UsageProviding {
    func fetch(_: Profile) async -> UsageFetchOutcome { .apiKeyMode }
}

/// Drops notifications.
private struct SilentNotifier: UsageNotifying {
    func deliver(_: [UsageNotification]) async {}
}
