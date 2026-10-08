// Tests Codex credentials, base URL, HTTP mapping, API-key mode and the session-log fallback.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct CodexUsageProviderTests {
    private let home: TemporaryHome
    private let files: RecordingFileSystem
    private let transport = FakeTransport()
    private let keychain = FakeKeychain()
    private let clock = FakeClock(now: Date(timeIntervalSince1970: 1_791_466_800))
    private let profile: Profile

    init() throws {
        home = try TemporaryHome()
        files = RecordingFileSystem(LocalFileSystem(homeDirectory: home.path))
        profile = Profile(provider: .codex, configDirectory: "\(home.path)/.codex", displayName: "Codex", order: 0)
    }

    private var provider: CodexUsageProvider {
        CodexUsageProvider(
            fileSystem: files, keychain: keychain, transport: transport, clock: clock, userAgent: "ChoscorUsage/0.1.0")
    }

    private func signIn(_ fixture: String = "codex-auth-chatgpt.json") throws {
        try home.write(".codex/auth.json", FixtureLoader.text(fixture))
    }

    private func installSessionLogs() throws {
        let names = [
            ("2026/10/07/rollout-2026-10-07T20-00-00-old.jsonl", 1_791_403_200.0),
            ("2026/10/08/rollout-2026-10-08T09-00-00-match.jsonl", 1_791_450_000.0),
            ("2026/10/08/rollout-2026-10-08T11-00-00-nolimits.jsonl", 1_791_457_200.0),
        ]
        for (name, modified) in names {
            try home.write(
                ".codex/sessions/\(name)", FixtureLoader.text("sessions/\(name)"),
                modified: Date(timeIntervalSince1970: modified))
        }
    }

    @Test func sendsBearerTokenAccountHeaderAndUserAgentToTheDefaultEndpoint() async throws {
        try signIn()
        transport.reply(.response(200, try FixtureLoader.data("codex-usage-5h-7d.json")), forHost: "chatgpt.com")
        let outcome = await provider.fetch(profile)
        let request = try #require(transport.requests.first)
        #expect(request.url.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.headers["Authorization"] == "Bearer synthetic-access")
        #expect(request.headers["ChatGPT-Account-Id"] == "acct-synthetic")
        #expect(request.headers["User-Agent"] == "ChoscorUsage/0.1.0")
        guard case .success(let snapshot) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(snapshot.windows.map(\.label) == ["5h", "7d"])
    }

    @Test func chatgptBaseURLInConfigTomlOverridesTheEndpoint() async throws {
        try signIn()
        try home.write(
            ".codex/config.toml",
            "# chatgpt_base_url = \"https://ignored.example\"\nmodel = \"x\"\nchatgpt_base_url = \"https://proxy.example/backend-api/\" # team\n"
        )
        _ = await provider.fetch(profile)
        #expect(transport.requests.first?.url.absoluteString == "https://proxy.example/backend-api/wham/usage")
    }

    @Test func apiKeyModeIsReportedWithoutARequest() async throws {
        try signIn("codex-auth-apikey.json")
        #expect(await provider.fetch(profile) == .apiKeyMode)
        #expect(transport.requests.isEmpty)
    }

    @Test func missingAuthFileIsCredentialsNotFound() async {
        #expect(await provider.fetch(profile) == .credentialsNotFound)
    }

    private var keyringItem: CodexKeychainItem {
        CodexKeychainItem(codexHome: profile.configDirectory, home: home.path)
    }

    @Test func keyringStoredCredentialsAreReadWhenThereIsNoAuthFile() async throws {
        keychain.set(
            keyringItem.service, account: keyringItem.account,
            .success(try FixtureLoader.data("codex-auth-chatgpt.json")))
        transport.reply(.response(200, try FixtureLoader.data("codex-usage-5h-7d.json")), forHost: "chatgpt.com")
        guard case .success = await provider.fetch(profile) else {
            Issue.record("expected success from keyring credentials")
            return
        }
        #expect(transport.requests.first?.headers["Authorization"] == "Bearer synthetic-access")
        #expect(keychain.reads == ["Codex Auth#\(keyringItem.account)"])
    }

    @Test func anAuthFileMeansTheKeychainIsNeverRead() async throws {
        try signIn()
        transport.reply(.response(200, try FixtureLoader.data("codex-usage-5h-7d.json")), forHost: "chatgpt.com")
        _ = await provider.fetch(profile)
        #expect(keychain.reads.isEmpty)
    }

    @Test func aDeniedKeyringReadIsKeychainDeniedWithoutARequest() async {
        keychain.set(keyringItem.service, account: keyringItem.account, .failure(.denied))
        #expect(await provider.fetch(profile) == .keychainDenied)
        #expect(transport.requests.isEmpty)
    }

    @Test func networkFailureFallsBackToTheNewestSessionLogRateLimits() async throws {
        try signIn()
        try installSessionLogs()
        transport.reply(.offline, forHost: "chatgpt.com")
        guard case .failed(_, let fallback?) = await provider.fetch(profile) else {
            Issue.record("expected a failure with fallback data")
            return
        }
        #expect(fallback.windows.map(\.label) == ["30d"])
        #expect(fallback.windows.map(\.usedPercent) == [33.5])
        #expect(fallback.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_793_000_000))
        #expect(fallback.source == .localLog(recordedAt: Date(timeIntervalSince1970: 1_791_451_200)))
        #expect(files.writtenPaths.isEmpty)
    }

    @Test func serverErrorAndUndecodableResponsesAlsoFallBack() async throws {
        try signIn()
        try installSessionLogs()
        transport.reply(.response(502, Data()), forHost: "chatgpt.com")
        guard case .failed(let detail, .some) = await provider.fetch(profile) else {
            Issue.record("expected 5xx fallback")
            return
        }
        #expect(detail == "Codex returned HTTP 502")
        transport.reply(.response(200, try FixtureLoader.data("codex-usage-changed.json")), forHost: "chatgpt.com")
        guard case .unsupportedResponse(.some) = await provider.fetch(profile) else {
            Issue.record("expected decode-failure fallback")
            return
        }
    }

    @Test func unauthorizedIsStaleAndNeverUsesTheFallback() async throws {
        try signIn()
        try installSessionLogs()
        transport.reply(.response(401, Data()), forHost: "chatgpt.com")
        #expect(await provider.fetch(profile) == .stale)
        transport.reply(.response(429, Data()), forHost: "chatgpt.com")
        #expect(await provider.fetch(profile) == .rateLimited)
    }

    @Test func aLongRunningOlderSessionWithTheNewestWriteWins() throws {
        try home.write(
            ".codex/sessions/2026/10/08/rollout-2026-10-08T09-00-00-match.jsonl",
            FixtureLoader.text("sessions/2026/10/08/rollout-2026-10-08T09-00-00-match.jsonl"),
            modified: Date(timeIntervalSince1970: 1_791_400_000))
        try home.write(
            ".codex/sessions/2026/10/07/rollout-2026-10-07T20-00-00-old.jsonl",
            FixtureLoader.text("sessions/2026/10/07/rollout-2026-10-07T20-00-00-old.jsonl"),
            modified: Date(timeIntervalSince1970: 1_791_460_000))
        let snapshot = CodexSessionLogReader(fileSystem: files).latestSnapshot(
            configDirectory: profile.configDirectory, now: clock.now)
        #expect(snapshot?.windows.map(\.usedPercent) == [5])
    }

    @Test func onlyTheTwentyNewestSessionFilesAreScanned() throws {
        let match = try FixtureLoader.text("sessions/2026/10/08/rollout-2026-10-08T09-00-00-match.jsonl")
        try home.write(".codex/sessions/2026/10/01/rollout-2026-10-01T00-00-00-match.jsonl", match)
        for index in 0..<20 {
            try home.write(
                ".codex/sessions/2026/10/08/rollout-2026-10-08T10-\(String(format: "%02d", index))-00-x.jsonl", "{}\n")
        }
        let reader = CodexSessionLogReader(fileSystem: files)
        #expect(reader.latestSnapshot(configDirectory: profile.configDirectory, now: clock.now) == nil)
        try FileManager.default.removeItem(
            atPath: "\(home.path)/.codex/sessions/2026/10/08/rollout-2026-10-08T10-00-00-x.jsonl")
        #expect(reader.latestSnapshot(configDirectory: profile.configDirectory, now: clock.now) != nil)
    }



    @Test func noSessionLogsMeansNoFallback() async throws {
        try signIn()
        transport.reply(.offline, forHost: "chatgpt.com")
        #expect(await provider.fetch(profile) == .failed(detail: "Couldn't reach Codex", fallback: nil))
    }
}
