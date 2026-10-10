// Tests that a Claude token is kept in memory between fetches and read again only when needed.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct ClaudeTokenCacheTests {
    private let home: TemporaryHome
    private let keychain = FakeKeychain()
    private let transport = FakeTransport()
    private let clock = FakeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
    private let profile: Profile
    private let provider: ClaudeUsageProvider
    private let host = "api.anthropic.com"

    init() throws {
        home = try TemporaryHome()
        profile = Profile(
            provider: .claude, configDirectory: "\(home.path)/.claude-work", displayName: "Work", order: 0)
        provider = ClaudeUsageProvider(
            credentials: ClaudeCredentialReader(
                keychain: keychain, directKeychain: FakeKeychain(),
                fileSystem: LocalFileSystem(homeDirectory: home.path)),
            transport: transport, clock: clock, userAgent: "ChoscorUsage/test")
        transport.reply(.response(200, Data(#"{"five_hour":{"utilization":5,"resets_at":null}}"#.utf8)), forHost: host)
        store(token: "t1", expiresIn: 3_600, service: ClaudeKeychainService.name(forConfigDir: profile.configDirectory))
    }

    private func store(token: String, expiresIn seconds: TimeInterval, service: String) {
        let millis = Int64(clock.now.addingTimeInterval(seconds).timeIntervalSince1970 * 1_000)
        keychain.set(
            service, .success(Data(#"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":\#(millis)}}"#.utf8)))
    }

    private func fetch(_ profile: Profile? = nil) async -> UsageFetchOutcome {
        await provider.fetch(profile ?? self.profile, allowingPrompt: false)
    }

    private var lastToken: String? { transport.requests.last?.headers["Authorization"] }

    @Test func anUnexpiredTokenIsReadOnceAcrossFetches() async {
        for _ in 0..<3 {
            _ = await fetch()
            clock.advance(by: .seconds(600))
        }
        #expect(keychain.reads.count == 1)
        #expect(transport.requests.count == 3)
        #expect(lastToken == "Bearer t1")
    }

    @Test func anExpiredCachedTokenIsReadAgainAndAStillExpiredOneIsStale() async {
        _ = await fetch()
        clock.advance(by: .seconds(3_600))
        #expect(await fetch() == .stale)
        #expect(keychain.reads.count == 2)
        store(token: "t2", expiresIn: 3_600, service: ClaudeKeychainService.name(forConfigDir: profile.configDirectory))
        _ = await fetch()
        #expect(keychain.reads.count == 3)
        #expect(lastToken == "Bearer t2")
    }

    @Test(arguments: [401, 403])
    func aRejectedTokenIsDropped(status: Int) async {
        transport.reply(.response(status, Data()), forHost: host)
        #expect(await fetch() == .stale)
        _ = await fetch()
        #expect(keychain.reads.count == 2)
    }

    @Test func discardingTheCacheForcesARead() async {
        _ = await fetch()
        provider.discardCachedCredentials(for: UUID())
        _ = await fetch()
        #expect(keychain.reads.count == 1, "another profile's discard keeps this entry")
        provider.discardCachedCredentials(for: profile.id)
        _ = await fetch()
        #expect(keychain.reads.count == 2)
    }

    @Test func aChangedOverrideOrDirectoryForcesARead() async {
        _ = await fetch()
        var picked = profile
        picked.keychainServiceOverride = "Claude Code-credentials-picked"
        store(token: "picked", expiresIn: 3_600, service: "Claude Code-credentials-picked")
        _ = await fetch(picked)
        #expect(lastToken == "Bearer picked")
        var moved = profile
        moved.configDirectory = "\(home.path)/.claude-moved"
        store(
            token: "moved", expiresIn: 3_600, service: ClaudeKeychainService.name(forConfigDir: moved.configDirectory))
        _ = await fetch(moved)
        #expect(lastToken == "Bearer moved")
        #expect(keychain.reads.count == 3)
    }
}
