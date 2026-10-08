// Tests the Claude fetch path: token checks, request headers and HTTP status mapping.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct ClaudeUsageProviderTests {
    private let home: TemporaryHome
    private let keychain = FakeKeychain()
    private let transport = FakeTransport()
    private let clock = FakeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
    private let profile: Profile

    init() throws {
        home = try TemporaryHome()
        profile = Profile(
            provider: .claude, configDirectory: "\(home.path)/.claude-work", displayName: "Work", order: 0)
    }

    private func store(token: String, expiresAt: Date) {
        let millis = Int64(expiresAt.timeIntervalSince1970 * 1_000)
        let json = #"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":\#(millis)}}"#
        keychain.set(ClaudeKeychainService.name(forConfigDir: profile.configDirectory), .success(Data(json.utf8)))
    }

    private var provider: ClaudeUsageProvider {
        ClaudeUsageProvider(
            credentials: ClaudeCredentialReader(
                keychain: keychain, fileSystem: LocalFileSystem(homeDirectory: home.path)),
            transport: transport, clock: clock, userAgent: "ChoscorUsage/0.1.0")
    }

    @Test func expiredTokenIsStaleWithoutAnyNetworkRequest() async {
        store(token: "old", expiresAt: clock.now.addingTimeInterval(-1))
        #expect(await provider.fetch(profile) == .stale)
        #expect(transport.requests.isEmpty)
    }

    @Test func validTokenSendsTheDocumentedRequestAndDecodesWindows() async throws {
        store(token: "secret-token", expiresAt: clock.now.addingTimeInterval(3_600))
        transport.reply(.response(200, try FixtureLoader.data("claude-usage-nulls.json")), forHost: "api.anthropic.com")
        let outcome = await provider.fetch(profile)
        let request = try #require(transport.requests.first)
        #expect(request.url.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.headers["Authorization"] == "Bearer secret-token")
        #expect(request.headers["anthropic-beta"] == "oauth-2025-04-20")
        #expect(request.headers["User-Agent"] == "ChoscorUsage/0.1.0")
        #expect(request.timeout == .seconds(15))
        guard case .success(let snapshot) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(snapshot.windows.map(\.label) == ["5h"])
        #expect(snapshot.fetchedAt == clock.now)
        #expect(snapshot.source == .endpoint)
    }

    @Test(arguments: [
        (401, UsageFetchOutcome.stale), (403, .stale), (429, .rateLimited),
        (500, .failed(detail: "Claude returned HTTP 500", fallback: nil)),
        (503, .failed(detail: "Claude returned HTTP 503", fallback: nil)),
    ])
    func httpStatusesMapToStates(status: Int, expected: UsageFetchOutcome) async {
        store(token: "t", expiresAt: clock.now.addingTimeInterval(3_600))
        transport.reply(.response(status, Data()), forHost: "api.anthropic.com")
        #expect(await provider.fetch(profile) == expected)
    }

    @Test func undecodableBodyIsAnUnsupportedResponse() async throws {
        store(token: "t", expiresAt: clock.now.addingTimeInterval(3_600))
        transport.reply(
            .response(200, try FixtureLoader.data("claude-usage-changed.json")), forHost: "api.anthropic.com")
        #expect(await provider.fetch(profile) == .unsupportedResponse(fallback: nil))
    }

    @Test func transportFailureIsAnError() async {
        store(token: "t", expiresAt: clock.now.addingTimeInterval(3_600))
        transport.reply(.offline, forHost: "api.anthropic.com")
        #expect(await provider.fetch(profile) == .failed(detail: "Couldn't reach Claude", fallback: nil))
    }

    @Test func credentialProblemsMapWithoutRequests() async {
        #expect(await provider.fetch(profile) == .keychainItemNotFound)
        keychain.set(ClaudeKeychainService.name(forConfigDir: profile.configDirectory), .failure(.denied))
        #expect(await provider.fetch(profile) == .keychainDenied)
        keychain.set(
            ClaudeKeychainService.name(forConfigDir: profile.configDirectory),
            .failure(.unavailable(status: -25_308)))
        #expect(await provider.fetch(profile) == .failed(detail: "Keychain is locked or unavailable", fallback: nil))
        #expect(transport.requests.isEmpty)
    }
}
