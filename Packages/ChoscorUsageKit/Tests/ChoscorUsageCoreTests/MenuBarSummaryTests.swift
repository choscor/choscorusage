// Tests the menu bar's worst-percentage summary, tint thresholds and empty state.
import Foundation
import Testing

@testable import ChoscorUsageCore

struct MenuBarSummaryTests {
    private func usage(
        _ name: String, order: Int, hidden: Bool = false, provider: Provider = .claude,
        _ windows: [(label: String, percent: Double, seconds: Int?)]
    ) -> ProfileUsage {
        let profile = Profile(
            provider: provider, configDirectory: "/Users/x/.\(name)", displayName: name, order: order, isHidden: hidden)
        let built = windows.enumerated().map { index, window in
            UsageWindow(
                id: "w\(index)", label: window.label, usedPercent: window.percent, resetsAt: nil,
                windowLength: window.seconds.map { .seconds($0) })
        }
        let snapshot = built.isEmpty ? nil : UsageSnapshot(windows: built, fetchedAt: .now, source: .endpoint)
        return ProfileUsage(profile: profile, state: .fresh, snapshot: snapshot)
    }

    @Test func showsTheHighestShortestWindowAcrossVisibleProfiles() {
        let summary = MenuBarSummary.make(from: [
            usage("Claude · work", order: 0, [("7d", 90, 604_800), ("5h", 72, 18_000)]),
            usage("Codex · personal", order: 1, provider: .codex, [("30d", 44, 2_592_000)]),
            usage("Claude · alt", order: 2, [("5h", 31, 18_000)]),
        ])
        #expect(summary.text == "72%")
        #expect(summary.tint == .normal)
        #expect(summary.accessibilityLabel == "Claude · work 72 percent of 5 hour limit")
    }

    @Test func codexUsesTheShortestWindowTheServerReturned() {
        let summary = MenuBarSummary.make(from: [
            usage("Codex", order: 0, provider: .codex, [("7d", 20, 604_800), ("12h", 64, 43_200)])
        ])
        #expect(summary.text == "64%")
        #expect(summary.accessibilityLabel == "Codex 64 percent of 12 hour limit")
    }

    @Test func hiddenProfilesAreIgnored() {
        let summary = MenuBarSummary.make(from: [
            usage("A", order: 0, [("5h", 10, 18_000)]),
            usage("B", order: 1, hidden: true, [("5h", 99, 18_000)]),
        ])
        #expect(summary.text == "10%")
    }

    @Test(arguments: [(79.9, MenuBarSummary.Tint.normal), (80, .warning), (94.9, .warning), (95, .critical)])
    func tintChangesAtEightyAndNinetyFive(percent: Double, tint: MenuBarSummary.Tint) {
        let summary = MenuBarSummary.make(from: [usage("A", order: 0, [("5h", percent, 18_000)])])
        #expect(summary.tint == tint)
    }

    @Test func showsADashWhenNoVisibleProfileHasData() {
        let summary = MenuBarSummary.make(from: [
            usage("A", order: 0, []), usage("B", order: 1, hidden: true, [("5h", 50, 18_000)]),
        ])
        #expect(summary.text == "—")
        #expect(summary.percent == nil)
        #expect(summary.tint == .normal)
    }

    @Test func aChosenProfileShowsItsMenuBadgeTintedByItsMostUsedWindow() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let chosen = usage("Codex", order: 1, provider: .codex, [("5h", 12, 18_000), ("7d", 85, 604_800)])
        let summary = MenuBarSummary.make(
            from: [usage("Claude", order: 0, [("5h", 90, 18_000)]), chosen], chosenProfileID: chosen.id, now: now)
        #expect(summary.text == ProfileMenuItem.make(from: chosen, now: now).badge)
        #expect(summary.text == "5h 12% • 7d 85%")
        #expect(summary.percent == 85)
        #expect(summary.tint == .warning)
        #expect(summary.accessibilityLabel == "Codex: 5h 12% • 7d 85%")
    }

    @Test func aChosenStaleClaudeProfileShowsItsWindowsWithoutTheProblem() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let profile = Profile(provider: .claude, configDirectory: "/Users/x/.claude-04", displayName: "04", order: 0)
        let windows = [
            UsageWindow(id: "five_hour", label: "5h", usedPercent: 0, resetsAt: nil, windowLength: .seconds(18_000)),
            UsageWindow(
                id: "seven_day_fable", label: "7d Fable", usedPercent: 0, resetsAt: now.addingTimeInterval(396_000),
                windowLength: .seconds(604_800)),
        ]
        let chosen = ProfileUsage(
            profile: profile, state: .stale(.claude),
            snapshot: UsageSnapshot(windows: windows, fetchedAt: now, source: .endpoint))
        let summary = MenuBarSummary.make(from: [chosen], chosenProfileID: profile.id, now: now)
        #expect(summary.text == "5h 0% • 7d Fable 0% (4d14h)")
    }

    @Test func aChosenProfileThatIsHiddenOrGoneFallsBackToTheWorstWindow() {
        let hidden = usage("B", order: 1, hidden: true, [("5h", 99, 18_000)])
        let usages = [usage("A", order: 0, [("5h", 10, 18_000)]), hidden]
        #expect(MenuBarSummary.make(from: usages, chosenProfileID: hidden.id, now: .now).text == "10%")
        #expect(MenuBarSummary.make(from: usages, chosenProfileID: UUID(), now: .now).text == "10%")
    }
}
