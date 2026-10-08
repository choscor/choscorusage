// Computes the menu bar text: the worst shortest-window percentage across visible profiles.

/// What the menu bar item shows: `NN%` from the most-used shortest window, tinted by severity.
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

    /// The displayed whole percentage, or `nil` when no visible profile has data.
    public let percent: Int?
    /// `NN%`, or `—` without data.
    public let text: String
    /// Severity tint for `text`.
    public let tint: Tint
    /// VoiceOver label naming the profile and window that supplied the value.
    public let accessibilityLabel: String

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
