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
}
