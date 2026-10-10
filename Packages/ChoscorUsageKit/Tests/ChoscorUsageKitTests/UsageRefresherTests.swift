// Tests state mapping, last-good retention, 429 backoff, Keychain denial and concurrency.
import ChoscorUsageCore
import ChoscorUsageProviders
import ChoscorUsageTestSupport
import Foundation
import Synchronization
import Testing

@testable import ChoscorUsageKit

struct UsageRefresherTests {
    private let home: TemporaryHome
    private let keychain = FakeKeychain()
    private let transport = FakeTransport()
    private let clock = FakeClock()
    private let profile: Profile
    private let host = "api.anthropic.com"

    init() throws {
        home = try TemporaryHome()
        profile = Profile(
            provider: .claude, configDirectory: "\(home.path)/.claude-work", displayName: "Work", order: 0)
        let json = #"{"claudeAiOauth":{"accessToken":"t","expiresAt":4102444800000}}"#
        keychain.set(ClaudeKeychainService.name(forConfigDir: profile.configDirectory), .success(Data(json.utf8)))
    }

    private func makeRefresher(minimumSpacing: [Provider: Duration] = [:]) -> UsageRefresher {
        let claude = ClaudeUsageProvider(
            credentials: ClaudeCredentialReader(
                keychain: keychain, directKeychain: FakeKeychain(),
                fileSystem: LocalFileSystem(homeDirectory: home.path)),
            transport: transport, clock: clock, userAgent: "ChoscorUsage/test")
        return UsageRefresher(providers: [.claude: claude], clock: clock, minimumSpacing: minimumSpacing)
    }

    private func usageBody(_ percent: Int) -> Data {
        Data(#"{"five_hour":{"utilization":\#(percent),"resets_at":"2027-01-01T00:00:00Z"}}"#.utf8)
    }

    private func refreshOnce(_ refresher: UsageRefresher) async -> ProfileUsage? {
        await refresher.refresh([profile]).first
    }

    @Test func successIsFreshAndFailuresKeepTheLastGoodData() async {
        let refresher = makeRefresher()
        transport.reply(.response(200, usageBody(42)), forHost: host)
        let fresh = await refreshOnce(refresher)
        #expect(fresh?.state == .fresh)
        let cases: [(Int, ProfileState)] = [
            (401, .stale(.claude)), (403, .stale(.claude)),
            (500, .error(detail: "Claude returned HTTP 500")), (200, .unsupportedResponse),
        ]
        for (status, expected) in cases {
            transport.reply(.response(status, status == 200 ? Data("[]".utf8) : Data()), forHost: host)
            let usage = await refreshOnce(refresher)
            #expect(usage?.state == expected)
            #expect(usage?.snapshot?.windows.first?.usedPercent == 42, "last good data kept for \(status)")
        }
    }

    @Test func aProviderSpacingSkipsEarlierRefreshesButNotRetry() async {
        let refresher = makeRefresher(minimumSpacing: [.claude: .seconds(180)])
        transport.reply(.response(200, usageBody(10)), forHost: host)
        _ = await refreshOnce(refresher)
        transport.reply(.response(200, usageBody(20)), forHost: host)
        clock.advance(by: .seconds(179))
        #expect(await refreshOnce(refresher)?.snapshot?.windows.first?.usedPercent == 10)
        #expect(transport.requests.count == 1)
        clock.advance(by: .seconds(1))
        #expect(await refreshOnce(refresher)?.snapshot?.windows.first?.usedPercent == 20)
        transport.reply(.response(200, usageBody(30)), forHost: host)
        #expect(await refresher.retry(profile).snapshot?.windows.first?.usedPercent == 30)
    }

    @Test func rateLimitBacksOffWithoutRequestsUntilTheRetryTime() async {
        let refresher = makeRefresher()
        transport.reply(.response(429, Data()), forHost: host)
        let first = await refreshOnce(refresher)
        #expect(first?.state == .rateLimited(retryAt: clock.now.addingTimeInterval(60)))
        clock.advance(by: .seconds(59))
        _ = await refreshOnce(refresher)
        #expect(transport.requests.count == 1)
        clock.advance(by: .seconds(1))
        let second = await refreshOnce(refresher)
        #expect(transport.requests.count == 2)
        #expect(second?.state == .rateLimited(retryAt: clock.now.addingTimeInterval(120)))
        clock.advance(by: .seconds(120))
        transport.reply(.response(200, usageBody(5)), forHost: host)
        #expect(await refreshOnce(refresher)?.state == .fresh)
    }

    @Test func anUnexpiredTokenIsReadFromTheKeychainOnceAcrossCycles() async {
        let refresher = makeRefresher()
        transport.reply(.response(200, usageBody(1)), forHost: host)
        for _ in 0..<3 {
            _ = await refreshOnce(refresher)
            clock.advance(by: .seconds(300))
        }
        #expect(keychain.reads.count == 1)
        #expect(transport.requests.count == 3)
    }

    @Test func keychainDenialStopsAutomaticPromptsUntilRetry() async {
        let refresher = makeRefresher()
        let service = ClaudeKeychainService.name(forConfigDir: profile.configDirectory)
        keychain.set(service, .failure(.denied))
        #expect(await refreshOnce(refresher)?.state == .keychainDenied)
        for _ in 0..<3 {
            #expect(await refreshOnce(refresher)?.state == .keychainDenied)
        }
        #expect(keychain.reads.count == 1)
        keychain.set(service, .success(Data(#"{"claudeAiOauth":{"accessToken":"t"}}"#.utf8)))
        transport.reply(.response(200, usageBody(7)), forHost: host)
        #expect(await refresher.retry(profile).state == .fresh)
        #expect(keychain.reads.count == 2)
    }

    @Test func hiddenProfilesAreNotFetched() async {
        var hidden = profile
        hidden.isHidden = true
        _ = await makeRefresher().refresh([hidden])
        #expect(keychain.reads.isEmpty && transport.requests.isEmpty)
    }

    @Test func atMostFourProfilesRefreshAtOnce() async {
        let gauge = ConcurrencyGauge()
        let refresher = UsageRefresher(providers: [.codex: gauge], clock: clock)
        let profiles = (0..<10).map {
            Profile(provider: .codex, configDirectory: "/tmp/.codex-\($0)", displayName: "\($0)", order: $0)
        }
        let usages = await refresher.refresh(profiles)
        #expect(usages.count == 10)
        #expect(gauge.peak == 4)
    }

    @Test func profilesWithoutAProviderAreErrorsAndDoNotStallTheQueue() async {
        let gauge = ConcurrencyGauge()
        let refresher = UsageRefresher(providers: [.codex: gauge], clock: clock)
        let profiles = (0..<8).map {
            Profile(
                provider: $0 < 4 ? .claude : .codex, configDirectory: "/tmp/.p-\($0)", displayName: "\($0)",
                order: $0)
        }
        let usages = await refresher.refresh(profiles)
        #expect(gauge.total == 4)
        #expect(usages.prefix(4).allSatisfy { $0.state == .error(detail: "Claude isn't supported") })
        #expect(usages.suffix(4).allSatisfy { $0.state == .apiKeyMode })
    }

    @Test func aRetryDuringARunningFetchRunsOnceThatFetchEndsWithoutOverlap() async {
        let gate = GatedProvider(outcome: .apiKeyMode)
        let refresher = UsageRefresher(providers: [.codex: gate], clock: clock)
        let codex = Profile(provider: .codex, configDirectory: "/tmp/.codex", displayName: "Codex", order: 0)
        async let refreshed = refresher.refresh([codex])
        await gate.waitUntilStarted(1)
        var picked = codex
        picked.keychainServiceOverride = "picked"
        _ = await refresher.retry(picked)
        gate.open()
        let final = await refreshed
        #expect(gate.started == 2, "the retry still runs, after the running fetch")
        #expect(gate.peak == 1, "never two fetches of one profile at once")
        #expect(final.first?.state == .apiKeyMode)
    }
}

/// A provider that records how many fetches overlap.
private final class ConcurrencyGauge: UsageProviding {
    private let state = Mutex((current: 0, peak: 0, total: 0))

    var peak: Int { state.withLock { $0.peak } }
    var total: Int { state.withLock { $0.total } }

    func fetch(_: Profile, allowingPrompt _: Bool) async -> UsageFetchOutcome {
        state.withLock { state in
            state.current += 1
            state.total += 1
            state.peak = max(state.peak, state.current)
        }
        try? await Task.sleep(for: .milliseconds(20))
        state.withLock { $0.current -= 1 }
        return .apiKeyMode
    }
}
