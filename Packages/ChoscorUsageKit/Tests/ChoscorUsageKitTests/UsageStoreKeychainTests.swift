// Tests that only Refresh Now and Retry may fall back to a Keychain read that can prompt.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageKit

@MainActor
struct UsageStoreKeychainTests {
    private let home: TemporaryHome
    private let defaults: UserDefaults
    private let clock = FakeClock()
    private let runner = FakeCommandRunner()
    private let direct = FakeKeychain()
    private let transport = FakeTransport()

    init() throws {
        home = try TemporaryHome()
        let suite = "ChoscorUsageKeychainTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let body = Data(#"{"five_hour":{"utilization":5,"resets_at":null}}"#.utf8)
        transport.reply(.response(200, body), forHost: "api.anthropic.com")
    }

    private func launch() async -> UsageStore {
        let files = LocalFileSystem(homeDirectory: home.path)
        let claude = ClaudeUsageProvider(
            credentials: ClaudeCredentialReader(
                keychain: SecurityCLIKeychainReader(runner: runner, attributes: direct), directKeychain: direct,
                fileSystem: files),
            transport: transport, clock: clock, userAgent: "ChoscorUsage/test")
        let store = UsageStore(
            dependencies: UsageDependencies(
                fileSystem: files, keychain: direct, environment: FakeEnvironment(), clock: clock,
                providers: [.claude: claude], notifier: Silent(), preferences: PreferencesStore(defaults: defaults)))
        await store.start()
        store.dismissCandidates()
        return store
    }

    @Test func onlyRefreshNowAndRetryFallBackToTheDirectRead() async throws {
        let store = await launch()
        let directory = "\(home.path)/.claude-work"
        let service = ClaudeKeychainService.name(forConfigDir: directory)
        runner.exit(36, forService: service)
        let millis = Int64(clock.now.addingTimeInterval(3_600).timeIntervalSince1970 * 1_000)
        direct.set(service, .success(Data(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":\#(millis)}}"#.utf8)))
        store.addProfile(provider: .claude, directory: directory)
        await store.flush()
        for trigger in [RefreshTrigger.timer, .wake, .menuOpened, .launch] {
            clock.advance(by: .seconds(120))
            await store.refresh(trigger)
        }
        #expect(direct.reads.isEmpty)
        #expect(store.usages.first?.state == .error(detail: "Keychain is locked or unavailable"))
        clock.advance(by: .seconds(30))
        await store.refresh(.manual)
        #expect(direct.reads == [service])
        #expect(store.usages.first?.state == .fresh)
        let id = try #require(store.profiles.first?.id)
        await store.retry(id)
        #expect(direct.reads == [service, service])
    }
}

private struct Silent: UsageNotifying {
    func deliver(_: [UsageNotification]) async {}
}
