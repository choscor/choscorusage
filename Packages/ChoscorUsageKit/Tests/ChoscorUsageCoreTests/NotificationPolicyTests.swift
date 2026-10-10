// Tests threshold and reset notifications, their dedupe, persistence and suppression.
import Foundation
import Testing

@testable import ChoscorUsageCore

struct NotificationPolicyTests {
    private let profile = Profile(
        provider: .claude, configDirectory: "/Users/x/.claude-work", displayName: "Work", order: 0)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var firstReset: Date { start.addingTimeInterval(3 * 3_600) }

    private func usage(
        _ percent: Double, resetsAt: Date?, state: ProfileState = .fresh, source: SnapshotSource = .endpoint
    ) -> ProfileUsage {
        let window = UsageWindow(
            id: "five_hour", label: "5h", usedPercent: percent, resetsAt: resetsAt, windowLength: .seconds(18_000))
        let snapshot = UsageSnapshot(windows: [window], fetchedAt: start, source: source)
        return ProfileUsage(profile: profile, state: state, snapshot: snapshot)
    }

    private func bodies(
        _ steps: [ProfileUsage], policy: NotificationPolicy = NotificationPolicy(), ledger: inout NotificationLedger
    ) -> [String] {
        steps.flatMap { policy.evaluate([$0], ledger: &ledger, now: start).map(\.body) }
    }

    @Test func anExtremeResetDateStillNotifiesWithoutTrapping() {
        var ledger = NotificationLedger()
        let events = NotificationPolicy().evaluate(
            [usage(85, resetsAt: Date(timeIntervalSince1970: 1e20))], ledger: &ledger, now: start)
        #expect(events.map(\.body) == ["5h window at 85%"])
        #expect(events.map(\.id) == ["\(profile.id.uuidString)|five_hour|none|percent80"])
    }

    @Test func aFractionalResetTimeIsStampedWithItsWholeMinute() {
        var ledger = NotificationLedger()
        let events = NotificationPolicy().evaluate(
            [usage(85, resetsAt: Date(timeIntervalSince1970: 1_800_010_799.943_648))], ledger: &ledger, now: start)
        #expect(events.map(\.id) == ["\(profile.id.uuidString)|five_hour|1800010800|percent80"])
    }

    @Test func notifiesOncePerThresholdCrossingAndOnReset() {
        var ledger = NotificationLedger()
        let nextReset = firstReset.addingTimeInterval(5 * 3_600)
        let steps = [
            usage(50, resetsAt: firstReset), usage(81, resetsAt: firstReset), usage(85, resetsAt: firstReset),
            usage(96, resetsAt: firstReset), usage(97, resetsAt: firstReset), usage(3, resetsAt: nextReset),
            usage(4, resetsAt: nextReset), usage(82, resetsAt: nextReset),
        ]
        #expect(
            bodies(steps, ledger: &ledger) == [
                "5h window at 81%", "5h window at 96%", "5h window reset", "5h window at 82%",
            ])
    }

    @Test func notificationCarriesOnlyTheDisplayNameLabelAndPercentage() throws {
        var ledger = NotificationLedger()
        let event = try #require(
            NotificationPolicy().evaluate([usage(88.7, resetsAt: firstReset)], ledger: &ledger, now: start).first)
        #expect(event.title == "Work")
        #expect(event.body == "5h window at 88%")
    }

    @Test func jumpingPastBothThresholdsNotifiesOnlyTheHigherOne() {
        var ledger = NotificationLedger()
        #expect(
            bodies([usage(10, resetsAt: firstReset), usage(99, resetsAt: firstReset)], ledger: &ledger) == [
                "5h window at 99%"
            ])
    }

    @Test func resetIsDetectedWhenResetTimeAdvancesEvenIfStillHigh() {
        var ledger = NotificationLedger()
        let later = firstReset.addingTimeInterval(5 * 3_600)
        let result = bodies([usage(85, resetsAt: firstReset), usage(90, resetsAt: later)], ledger: &ledger)
        #expect(result == ["5h window at 85%", "5h window reset", "5h window at 90%"])
    }

    @Test func dedupeSurvivesARelaunchThroughPersistence() throws {
        var ledger = NotificationLedger()
        _ = bodies([usage(83, resetsAt: firstReset)], ledger: &ledger)
        var restored = try JSONDecoder().decode(NotificationLedger.self, from: JSONEncoder().encode(ledger))
        #expect(bodies([usage(84, resetsAt: firstReset)], ledger: &restored).isEmpty)
        #expect(
            bodies([usage(1, resetsAt: firstReset.addingTimeInterval(18_000))], ledger: &restored) == [
                "5h window reset"
            ])
    }

    @Test func togglesSilenceTheirKindOfAlert() {
        var ledger = NotificationLedger()
        let quietThresholds = NotificationPolicy(thresholdAlertsEnabled: false, resetAlertsEnabled: true)
        let steps = [usage(90, resetsAt: firstReset), usage(2, resetsAt: firstReset.addingTimeInterval(18_000))]
        #expect(bodies(steps, policy: quietThresholds, ledger: &ledger) == ["5h window reset"])
        var other = NotificationLedger()
        let quietResets = NotificationPolicy(thresholdAlertsEnabled: true, resetAlertsEnabled: false)
        #expect(bodies(steps, policy: quietResets, ledger: &other) == ["5h window at 90%"])
    }

    @Test(arguments: [ProfileState.stale(.claude), .error(detail: "offline"), .rateLimited(retryAt: .distantFuture)])
    func staleErrorAndRateLimitedDataNeverNotify(state: ProfileState) {
        var ledger = NotificationLedger()
        #expect(bodies([usage(99, resetsAt: firstReset, state: state)], ledger: &ledger).isEmpty)
    }

    @Test func localLogDataNotifiesOnlyWhileAtMostThirtyMinutesOld() {
        var ledger = NotificationLedger()
        let old = usage(
            90, resetsAt: firstReset, state: .error(detail: "offline"),
            source: .localLog(recordedAt: start.addingTimeInterval(-31 * 60)))
        #expect(bodies([old], ledger: &ledger).isEmpty)
        let recent = usage(
            90, resetsAt: firstReset, state: .error(detail: "offline"),
            source: .localLog(recordedAt: start.addingTimeInterval(-10 * 60)))
        #expect(bodies([recent], ledger: &ledger) == ["5h window at 90%"])
    }

    @Test func windowsWithoutAResetTimeAlertAgainInEveryCycle() {
        var ledger = NotificationLedger()
        let cycle = [usage(85, resetsAt: nil), usage(40, resetsAt: nil)]
        #expect(
            bodies(cycle + cycle, ledger: &ledger) == [
                "5h window at 85%", "5h window reset", "5h window at 85%", "5h window reset",
            ])
    }

    @Test func resetTimeJitterAcrossAMinuteBoundaryDoesNotRepeatAnAlert() {
        var ledger = NotificationLedger()
        let boundary = Date(timeIntervalSince1970: 1_800_010_800)
        let steps = [
            usage(82, resetsAt: boundary.addingTimeInterval(29.9)),
            usage(83, resetsAt: boundary.addingTimeInterval(30.1)),
            usage(84, resetsAt: boundary.addingTimeInterval(31)),
        ]
        #expect(bodies(steps, ledger: &ledger) == ["5h window at 82%"])
    }

    @Test(arguments: [ProfileState.stale(.codex), .rateLimited(retryAt: .distantFuture), .keychainDenied])
    func recentLocalLogDataStillRespectsStaleAndRateLimitedStates(state: ProfileState) {
        var ledger = NotificationLedger()
        let recent = usage(
            90, resetsAt: firstReset, state: state, source: .localLog(recordedAt: start.addingTimeInterval(-60)))
        #expect(bodies([recent], ledger: &ledger).isEmpty)
    }

    @Test func hiddenProfilesNeverNotify() {
        var ledger = NotificationLedger()
        var hidden = profile
        hidden.isHidden = true
        let usage = ProfileUsage(profile: hidden, state: .fresh, snapshot: usage(99, resetsAt: firstReset).snapshot)
        #expect(NotificationPolicy().evaluate([usage], ledger: &ledger, now: start).isEmpty)
    }

    @Test func theLedgerDropsKeysForWindowsTheSnapshotNoLongerHas() {
        var ledger = NotificationLedger()
        let other = Profile(provider: .codex, configDirectory: "/Users/x/.codex", displayName: "Codex", order: 1)
        let windows = [
            UsageWindow(id: "five_hour", label: "5h", usedPercent: 85, resetsAt: firstReset, windowLength: nil),
            UsageWindow(id: "iguana_necktie", label: "i", usedPercent: 90, resetsAt: firstReset, windowLength: nil),
            UsageWindow(id: "extra_usage", label: "Extra", usedPercent: 90, resetsAt: nil, windowLength: nil),
        ]
        func usage(_ profile: Profile, _ windows: [UsageWindow]?) -> ProfileUsage {
            let snapshot = windows.map { UsageSnapshot(windows: $0, fetchedAt: start, source: .endpoint) }
            return ProfileUsage(profile: profile, state: .fresh, snapshot: snapshot)
        }
        let policy = NotificationPolicy()
        _ = policy.evaluate([usage(profile, windows), usage(other, windows)], ledger: &ledger, now: start)
        #expect(Set(ledger.delivered.map(\.windowID)) == ["five_hour", "iguana_necktie", "extra_usage"])
        _ = policy.evaluate([usage(profile, [windows[0]]), usage(other, nil)], ledger: &ledger, now: start)
        let mine = "\(profile.id.uuidString)|"
        #expect(Set(ledger.delivered.filter { $0.profileID == profile.id }.map(\.windowID)) == ["five_hour"])
        #expect(ledger.armed.keys.filter { $0.hasPrefix(mine) } == ["\(mine)five_hour"])
        #expect(!ledger.armedWithoutReset.contains { $0.hasPrefix(mine) })
        #expect(ledger.delivered.filter { $0.profileID == other.id }.count == 3, "no snapshot: keys are kept")
        #expect(ledger.armedWithoutReset.contains("\(other.id.uuidString)|extra_usage"))
    }

    @Test(arguments: [
        (ProfileState.fresh, SnapshotSource.localLog(recordedAt: Date(timeIntervalSince1970: 1_800_000_000))),
        (.error(detail: "offline"), .endpoint),
    ])
    func onlyAFreshEndpointSnapshotPrunesMissingWindows(state: ProfileState, source: SnapshotSource) {
        var ledger = NotificationLedger()
        let five = UsageWindow(id: "five_hour", label: "5h", usedPercent: 10, resetsAt: firstReset, windowLength: nil)
        let extra = UsageWindow(
            id: "Spark.primary_window", label: "Spark 5h", usedPercent: 90, resetsAt: firstReset, windowLength: nil)
        let full = UsageSnapshot(windows: [five, extra], fetchedAt: start, source: .endpoint)
        _ = NotificationPolicy().evaluate(
            [ProfileUsage(profile: profile, state: .fresh, snapshot: full)], ledger: &ledger, now: start)
        let partial = UsageSnapshot(windows: [full.windows[0]], fetchedAt: start, source: source)
        _ = NotificationPolicy().evaluate(
            [ProfileUsage(profile: profile, state: state, snapshot: partial)], ledger: &ledger, now: start)
        #expect(ledger.delivered.map(\.windowID) == ["Spark.primary_window"])
        #expect(ledger.armed.keys.contains("\(profile.id.uuidString)|Spark.primary_window"))
    }
}
