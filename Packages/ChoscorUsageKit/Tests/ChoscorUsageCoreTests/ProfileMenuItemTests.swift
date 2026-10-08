// Tests the text and action of each profile's row in the menu bar menu.
import Foundation
import Testing

@testable import ChoscorUsageCore

struct ProfileMenuItemTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func usage(
        _ state: ProfileState, name: String = "Claude · 01", provider: Provider = .claude,
        fetchedSecondsAgo: TimeInterval = 120, source: SnapshotSource = .endpoint,
        _ windows: [(label: String, percent: Double, resetIn: TimeInterval?)]
    ) -> ProfileUsage {
        let profile = Profile(provider: provider, configDirectory: "/Users/x/.claude", displayName: name, order: 0)
        let built = windows.enumerated().map { index, window in
            UsageWindow(
                id: "w\(index)", label: window.label, usedPercent: window.percent,
                resetsAt: window.resetIn.map { now.addingTimeInterval($0) }, windowLength: nil)
        }
        let fetchedAt = now.addingTimeInterval(-fetchedSecondsAgo)
        let snapshot = windows.isEmpty ? nil : UsageSnapshot(windows: built, fetchedAt: fetchedAt, source: source)
        return ProfileUsage(profile: profile, state: state, snapshot: snapshot)
    }

    @Test func freshProfileShowsEveryWindowWithItsResetInline() {
        let item = ProfileMenuItem.make(
            from: usage(.fresh, [("5h", 72.6, 4_320), ("7d", 30, 273_600), ("30d", 5, nil)]), now: now)
        #expect(item.badge == "5h 72% · 1h12m · 7d 30% · 3d4h · 30d 5%")
        #expect(item.rowTitle == "\(item.title) — 5h 72% · 1h12m · 7d 30% · 3d4h · 30d 5%")
        #expect(item.message == nil)
        #expect(item.action == nil)
    }

    @Test(arguments: [
        ("Claude · 01", Provider.claude, "01"),
        ("Codex · team", .codex, "team"),
        ("Claude", .claude, "Default"),
        ("Codex", .codex, "Default"),
        ("Work account", .claude, "Work account"),
        ("Codex · x", .claude, "Codex · x"),
    ])
    func titleDropsTheProviderNameTheLogoAlreadyShows(name: String, provider: Provider, title: String) {
        let item = ProfileMenuItem.make(from: usage(.fresh, name: name, provider: provider, []), now: now)
        #expect(item.title == title)
    }

    @Test(arguments: [
        (ProfileState.keychainDenied, "Needs Keychain access", ProfileMenuItem.Action?.some(.retry)),
        (.keychainItemNotFound, "Keychain item missing", .openSettings),
        (.credentialsNotFound, "No credentials", .openSettings),
        (.stale(.claude), "Open Claude Code", nil),
        (.stale(.codex), "Sign in again", nil),
        (.rateLimited(retryAt: .distantFuture), "Rate limited", nil),
        (.error(detail: "Couldn't reach Claude"), "Refresh failed", nil),
        (.unsupportedResponse, "Update needed", nil),
        (.apiKeyMode, "API key mode", nil),
    ])
    func problemsShowAShortBadgeTheFullMessageAndTheirFix(
        state: ProfileState, badge: String, action: ProfileMenuItem.Action?
    ) {
        let item = ProfileMenuItem.make(from: usage(state, []), now: now)
        #expect(item.badge == badge)
        #expect(item.message == state.message)
        #expect(item.action == action)
    }

    @Test func problemKeepsTheLastKnownWindowsBesideIt() {
        let item = ProfileMenuItem.make(from: usage(.rateLimited(retryAt: .distantFuture), [("5h", 40, 600)]), now: now)
        #expect(item.badge == "Rate limited · 5h 40% · 10m")
    }

    @Test(arguments: [(ProfileState.notLoaded, "Loading…"), (.fresh, "No usage data")])
    func profileWithoutDataSaysWhy(state: ProfileState, badge: String) {
        let item = ProfileMenuItem.make(from: usage(state, []), now: now)
        #expect(item.badge == badge)
    }

    @Test func lastUpdatedUsesTheNewestFetchAcrossProfiles() {
        let usages = [
            usage(.fresh, fetchedSecondsAgo: 600, [("5h", 1, nil)]),
            usage(.keychainDenied, fetchedSecondsAgo: 120, [("5h", 1, nil)]),
            usage(.notLoaded, []),
        ]
        #expect(ProfileMenuItem.lastUpdated(usages, now: now) == "Updated 2m ago")
        #expect(ProfileMenuItem.lastUpdated([usage(.notLoaded, [])], now: now) == nil)
    }

    @Test func lastUpdatedUsesWhenLocalLogDataWasRecordedNotWhenItWasRead() {
        let log = usage(
            .fresh, provider: .codex, fetchedSecondsAgo: 0,
            source: .localLog(recordedAt: now.addingTimeInterval(-3_600)),
            [("5h", 1, nil)])
        #expect(ProfileMenuItem.lastUpdated([log], now: now) == "Updated 1h ago")
    }
}
