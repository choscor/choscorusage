// Computes the menu bar text: a chosen profile's menu badge, or the worst shortest-window percentage.
import Foundation

/// What the menu bar item shows: the chosen profile's menu badge, or `NN%` from the most-used
/// shortest window, tinted by severity.
public struct MenuBarSummary: Equatable, Sendable {
    /// Severity color for the menu bar text.
    public enum Tint: Sendable {
        /// Below 80%.
        case normal
        /// 80% or more.
        case warning
        /// 95% or more.
        case critical
    }

    /// The whole percentage that sets the tint, or `nil` when no visible profile has data.
    public let percent: Int?
    /// The chosen profile's badge, `NN%`, or `—` without data.
    public let text: String
    /// Severity tint for `text`.
    public let tint: Tint
    /// VoiceOver label naming the profile and window that supplied the value.
    public let accessibilityLabel: String

    /// Shows the visible profile `chosenProfileID` names exactly as its menu row's badge, with
    /// countdowns from `now` and the tint of its most-used window; otherwise falls back to
    /// ``make(from:)``, so a hidden or removed choice never blanks the menu bar. Pure; any thread.
    public static func make(from usages: [ProfileUsage], chosenProfileID: UUID?, now: Date) -> Self {
        guard let chosen = usages.first(where: { $0.id == chosenProfileID && !$0.profile.isHidden }) else {
            return make(from: usages)
        }
        let badge = ProfileMenuItem.make(from: chosen, now: now).badge
        let mostUsed = chosen.snapshot?.windows.map(\.usedPercent).max()
        return Self(
            percent: mostUsed.map { Int($0.rounded(.down)) },
            text: badge,
            tint: mostUsed.map(tint(for:)) ?? .normal,
            accessibilityLabel: "\(chosen.profile.displayName): \(badge)"
        )
    }

    /// Summarizes visible profiles in user order. For each profile only its shortest window
    /// with data counts (Claude's `5h`; Codex's shortest returned window); the highest wins and
    /// ties go to the earlier profile.
    public static func make(from usages: [ProfileUsage]) -> Self {
        let visible = usages.filter { !$0.profile.isHidden }.sorted { $0.profile.order < $1.profile.order }
        var worst: (profile: Profile, window: UsageWindow)?
        for usage in visible {
            guard let window = shortestWindow(in: usage.snapshot?.windows ?? []) else {
                continue
            }
            if window.usedPercent > worst?.window.usedPercent ?? -1 {
                worst = (usage.profile, window)
            }
        }
        guard let worst else {
            return Self(percent: nil, text: "—", tint: .normal, accessibilityLabel: "No usage data")
        }
        let percent = Int(worst.window.usedPercent.rounded(.down))
        let limit = worst.window.windowLength.map { WindowLabel.spoken(forSeconds: Int($0.components.seconds)) }
        return Self(
            percent: percent,
            text: "\(percent)%",
            tint: tint(for: worst.window.usedPercent),
            accessibilityLabel:
                "\(worst.profile.displayName) \(percent) percent of \(limit ?? worst.window.label) limit"
        )
    }

    /// Returns the tint for a percentage: orange from 80, red from 95.
    public static func tint(for usedPercent: Double) -> Tint {
        if usedPercent >= 95 {
            return .critical
        }
        return usedPercent >= 80 ? .warning : .normal
    }

    private static func shortestWindow(in windows: [UsageWindow]) -> UsageWindow? {
        let timed = windows.filter { $0.windowLength != nil }
        return timed.min { ($0.windowLength ?? .zero) < ($1.windowLength ?? .zero) } ?? windows.first
    }
}
