// Tests which Keychain reader each refresh uses, and when a cached Claude token is read again.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageKit

struct UsageRefresherKeychainTests {
    private let home: TemporaryHome
    private let runner = FakeCommandRunner()
    private let direct = FakeKeychain()
    private let transport = FakeTransport()
    private let clock = FakeClock()
    private let profile: Profile
    private let service: String
    private let refresher: UsageRefresher

    init() throws {
        home = try TemporaryHome()
        profile = Profile(
            provider: .claude, configDirectory: "\(home.path)/.claude-work", displayName: "Work", order: 0)
        service = ClaudeKeychainService.name(forConfigDir: profile.configDirectory)
        let cli = SecurityCLIKeychainReader(runner: runner, attributes: direct)
        let claude = ClaudeUsageProvider(
            credentials: ClaudeCredentialReader(
                keychain: cli, directKeychain: direct, fileSystem: LocalFileSystem(homeDirectory: home.path)),
            transport: transport, clock: clock, userAgent: "ChoscorUsage/test")
        refresher = UsageRefresher(providers: [.claude: claude], clock: clock)
        let body = Data(#"{"five_hour":{"utilization":5,"resets_at":null}}"#.utf8)
        transport.reply(.response(200, body), forHost: "api.anthropic.com")
        direct.set(service, .success(Data(credentials.utf8)))
    }

    /// A token that expires an hour after the test starts.
    private var credentials: String {
        let millis = Int64(clock.now.addingTimeInterval(3_600).timeIntervalSince1970 * 1_000)
        return #"{"claudeAiOauth":{"accessToken":"t","expiresAt":\#(millis)}}"#
    }

    private func printCredentials() {
        runner.output(credentials, forService: service)
    }

    @Test func anAutomaticRefreshReadsThroughTheCLIAndNeverTheDirectReader() async {
        printCredentials()
        #expect(await refresher.refresh([profile]).first?.state == .fresh)
        #expect(runner.calls.count == 1 && direct.reads.isEmpty)
    }

    @Test func aFailingCLIFallsBackToTheDirectReadOnlyOnAUserAction() async {
        runner.exit(36, forService: service)
        #expect(await refresher.refresh([profile]).first?.state == .error(detail: "Keychain is locked or unavailable"))
        #expect(direct.reads.isEmpty)
        clock.advance(by: .seconds(60))
        #expect(await refresher.refresh([profile], allowingPrompt: true).first?.state == .fresh)
        #expect(direct.reads == [service])
    }

    @Test func aCachedTokenNeedsNoCLICallUntilItExpires() async {
        printCredentials()
        _ = await refresher.refresh([profile])
        clock.advance(by: .seconds(1_800))
        _ = await refresher.refresh([profile])
        #expect(runner.calls.count == 1)
        clock.advance(by: .seconds(1_800))
        #expect(await refresher.refresh([profile]).first?.state == .stale(.claude))
        #expect(runner.calls.count == 2)
    }

    @Test func retryAndRemovalEachForceARead() async {
        printCredentials()
        _ = await refresher.refresh([profile])
        _ = await refresher.retry(profile)
        #expect(runner.calls.count == 2)
        await refresher.forget(except: [])
        _ = await refresher.refresh([profile])
        #expect(runner.calls.count == 3)
    }

    @Test func aCLIDenialGatesAutomaticRefreshesUntilRetry() async {
        runner.exit(128, forService: service)
        #expect(await refresher.refresh([profile]).first?.state == .keychainDenied)
        for _ in 0..<3 {
            #expect(await refresher.refresh([profile], allowingPrompt: true).first?.state == .keychainDenied)
        }
        #expect(runner.calls.count == 1 && direct.reads.isEmpty)
        printCredentials()
        #expect(await refresher.retry(profile).state == .fresh)
        #expect(runner.calls.count == 2)
    }
}
