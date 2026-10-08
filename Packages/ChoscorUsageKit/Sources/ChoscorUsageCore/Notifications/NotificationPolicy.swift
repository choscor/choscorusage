// Decides which threshold and reset notifications a set of fresh readings should raise.
import Foundation

/// Emits an alert when a window first reaches 80% and 95%, and when a window that reached
/// 80% resets. Stale, failing and rate-limited profiles never notify; local-log readings
/// notify only while at most 30 minutes old.
public struct NotificationPolicy: Sendable {
    /// Whether 80%/95% alerts are delivered.
    public var thresholdAlertsEnabled: Bool
    /// Whether reset alerts are delivered.
    public var resetAlertsEnabled: Bool

    private static let warning = 80.0
    private static let critical = 95.0
    private static let maximumLogAge: TimeInterval = 30 * 60
    private static let resetJitter: TimeInterval = 60

    /// Creates a policy; both alert kinds are on by default.
    public init(thresholdAlertsEnabled: Bool = true, resetAlertsEnabled: Bool = true) {
        self.thresholdAlertsEnabled = thresholdAlertsEnabled
        self.resetAlertsEnabled = resetAlertsEnabled
    }

    /// Returns the alerts to deliver for `usages` and records them in `ledger`. Disabled kinds
    /// are still recorded, so turning a toggle on later does not replay old crossings.
    public func evaluate(_ usages: [ProfileUsage], ledger: inout NotificationLedger, now: Date) -> [UsageNotification] {
        var events: [UsageNotification] = []
        for usage in usages where Self.isEligible(usage, now: now) {
            for window in usage.snapshot?.windows ?? [] {
                events += evaluate(window, of: usage.profile, ledger: &ledger)
            }
        }
        ledger.prune(before: now)
        return events
    }

    private static func isEligible(_ usage: ProfileUsage, now: Date) -> Bool {
        guard !usage.profile.isHidden, let snapshot = usage.snapshot else {
            return false
        }
        switch usage.state {
        case .fresh:
            break
        case .error, .unsupportedResponse:
            // Only a recent Codex local-log fallback may still notify while the endpoint fails.
            guard case .localLog = snapshot.source else {
                return false
            }
        default:
            return false
        }
        if case .localLog(let recordedAt) = snapshot.source {
            return now.timeIntervalSince(recordedAt) <= maximumLogAge
        }
        return true
    }

    private func evaluate(
        _ window: UsageWindow, of profile: Profile, ledger: inout NotificationLedger
    )
        -> [UsageNotification]
    {
        let windowKey = "\(profile.id.uuidString)|\(window.id)"
        var events: [UsageNotification] = []
        if let reset = resetEvent(window, of: profile, windowKey: windowKey, ledger: &ledger) {
            events.append(reset)
        }
        guard window.usedPercent >= Self.warning else {
            return events
        }
        // Codex derives reset times from `reset_after_seconds`, which drifts with request latency;
        // within the jitter the armed time stays the window's identity so keys do not change.
        var resetsAt = window.resetsAt
        if let armed = ledger.armed[windowKey], let current = resetsAt,
            abs(current.timeIntervalSince(armed)) <= Self.resetJitter
        {
            resetsAt = armed
        }
        ledger.arm(windowKey, resetsAt: resetsAt)
        let crossed: NotificationLedger.Kind = window.usedPercent >= Self.critical ? .percent95 : .percent80
        let key = Self.key(profile, window.id, resetsAt, crossed)
        let isNew = ledger.record(key)
        if crossed == .percent95 {
            _ = ledger.record(Self.key(profile, window.id, resetsAt, .percent80))
        }
        if isNew && thresholdAlertsEnabled {
            let percent = Int(window.usedPercent.rounded(.down))
            events.append(Self.notification(key, profile, "\(window.label) window at \(percent)%"))
        }
        return events
    }

    private func resetEvent(
        _ window: UsageWindow, of profile: Profile, windowKey: String, ledger: inout NotificationLedger
    ) -> UsageNotification? {
        guard ledger.isArmed(windowKey) else {
            return nil
        }
        let armedReset = ledger.armed[windowKey]
        var advanced = false
        if let armedReset, let current = window.resetsAt {
            advanced = current.timeIntervalSince(armedReset) > Self.resetJitter
        }
        guard advanced || window.usedPercent < Self.warning else {
            return nil
        }
        ledger.disarm(windowKey, profileID: profile.id, windowID: window.id)
        let key = Self.key(profile, window.id, armedReset, .reset)
        // Disarming already prevents a repeat; undated reset keys are not kept across cycles.
        guard armedReset == nil || ledger.record(key), resetAlertsEnabled else {
            return nil
        }
        return Self.notification(key, profile, "\(window.label) window reset")
    }

    private static func key(
        _ profile: Profile, _ windowID: String, _ resetsAt: Date?, _ kind: NotificationLedger.Kind
    )
        -> NotificationLedger.Key
    {
        let minute = resetsAt.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 60).rounded() * 60) }
        return NotificationLedger.Key(profileID: profile.id, windowID: windowID, resetsAt: minute, kind: kind)
    }

    private static func notification(
        _ key: NotificationLedger.Key, _ profile: Profile, _ body: String
    )
        -> UsageNotification
    {
        let stamp = key.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        let id = "\(key.profileID.uuidString)|\(key.windowID)|\(stamp)|\(key.kind.rawValue)"
        return UsageNotification(id: id, title: profile.displayName, body: body)
    }
}
