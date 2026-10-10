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
        #expect(item.badge == "5h 72% (1h12m) • 7d 30% (3d4h) • 30d 5%")
        #expect(item.rowTitle == "\(item.title) — 5h 72% (1h12m) • 7d 30% (3d4h) • 30d 5%")
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
        #expect(item.badge == "Rate limited • 5h 40% (10m)")
    }

    @Test(arguments: [
        ApprovedRow([("5h", 4, 16_500), ("7d Fable", 0, 442_800)], "5h 4% (4h35m) • 7d Fable 0% (5d3h)"),
        ApprovedRow([("5h", 0, nil), ("7d Fable", 0, 493_200)], "5h 0% • 7d Fable 0% (5d17h)"),
        ApprovedRow([("5h", 0, 30), ("7d", 53, 198_000)], "5h 0% (<1m) • 7d 53% (2d7h)"),
        ApprovedRow([("30d", 53, 2_163_600)], "30d 53% (25d1h)"),
    ])
    func freshRowsMatchTheApprovedVariations(row: ApprovedRow) {
        let item = ProfileMenuItem.make(from: usage(.fresh, row.windows), now: now)
        #expect(item.badge == row.badge)
    }

    @Test func staleClaudeWithDataShowsOnlyTheWindowsAndKeepsTheFullTooltip() {
        let item = ProfileMenuItem.make(
            from: usage(.stale(.claude), [("5h", 0, nil), ("7d Fable", 0, 396_000)]), now: now)
        #expect(item.badge == "5h 0% • 7d Fable 0% (4d14h)")
        #expect(item.message == ProfileState.stale(.claude).message)
    }

    @Test func staleCodexWithDataStillLeadsWithItsProblem() {
        let item = ProfileMenuItem.make(from: usage(.stale(.codex), provider: .codex, [("30d", 5, nil)]), now: now)
        #expect(item.badge == "Sign in again • 30d 5%")
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

/// One approved badge preview: windows as `(label, percent, seconds until reset)`.
struct ApprovedRow: Sendable {
    let windows: [(label: String, percent: Double, resetIn: TimeInterval?)]
    let badge: String

    init(_ windows: [(label: String, percent: Double, resetIn: TimeInterval?)], _ badge: String) {
        self.windows = windows
        self.badge = badge
    }
}
