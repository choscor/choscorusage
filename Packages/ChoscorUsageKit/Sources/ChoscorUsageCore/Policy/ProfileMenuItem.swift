// Builds the text and action for one profile's row in the menu bar menu.
import Foundation

/// What the menu shows for a profile on a single row: a name beside the provider logo, followed
/// by every window or a few words naming the problem.
public struct ProfileMenuItem: Equatable, Sendable {
    /// The action that resolves a profile's problem.
    public enum Action: Equatable, Sendable {
        /// Ask for Keychain access again; the only path that prompts after a denial.
        case retry
        /// Open Settings to fix the profile's directory or Keychain item.
        case openSettings
    }

    /// The display name without the provider prefix the logo already shows.
    public let title: String
    /// Every window as `5h 72% (1h12m)` (reset countdown in parentheses), joined by ` • `, led by a
    /// short problem when there is one.
    public let badge: String
    /// The row's full text, `<title> — <badge>`. Menu-item badges are drawn at a fixed small font,
    /// so the usage shares the title to render at the normal menu size.
    public var rowTitle: String { "\(title) — \(badge)" }
    /// The state's full message when the profile is not healthy, for the row's tooltip.
    public let message: String?
    /// The action the row performs, if the user can resolve its state.
    public let action: Action?

    /// Builds the row for `usage` with countdowns measured from `now`. Pure; any thread.
    public static func make(from usage: ProfileUsage, now: Date) -> Self {
        Self(
            title: shortTitle(for: usage.profile),
            badge: badge(for: usage, now: now),
            message: usage.state.message,
            action: resolvingAction(for: usage.state)
        )
    }

    /// `Updated <age>` from the newest observation across `usages`, or `nil` when none has data. The
    /// menu shows one such row because a refresh updates every profile together.
    public static func lastUpdated(_ usages: [ProfileUsage], now: Date) -> String? {
        // `observedAt`, not `fetchedAt`: a Codex local-log reading is as old as its log line.
        guard let newest = usages.compactMap(\.snapshot?.observedAt).max() else {
            return nil
        }
        return "Updated \(CompactDuration.age(now.timeIntervalSince(newest)))"
    }

    private static let separator = " • "

    /// A problem leads, but the last known windows stay beside it so a failed refresh does not
    /// hide the numbers. A stale Claude token is routine (it renews whenever Claude Code runs),
    /// so it gives way to the windows and keeps its advice in the tooltip.
    private static func badge(for usage: ProfileUsage, now: Date) -> String {
        let windows = usage.snapshot?.windows ?? []
        guard let problem = shortProblem(usage.state) else {
            return summary(windows, state: usage.state, now: now)
        }
        if windows.isEmpty {
            return problem
        }
        let summary = summary(windows, state: usage.state, now: now)
        return usage.state == .stale(.claude) ? summary : "\(problem)\(separator)\(summary)"
    }

    /// Default names are `<Provider> · <suffix>` or just `<Provider>`; renamed profiles are kept.
    private static func shortTitle(for profile: Profile) -> String {
        let provider = profile.provider.displayName
        if profile.displayName == provider {
            return "Default"
        }
        let prefix = "\(provider) · "
        guard profile.displayName.hasPrefix(prefix), profile.displayName.count > prefix.count else {
            return profile.displayName
        }
        return String(profile.displayName.dropFirst(prefix.count))
    }

    private static func resolvingAction(for state: ProfileState) -> Action? {
        switch state {
        case .keychainDenied: .retry
        case .keychainItemNotFound, .credentialsNotFound: .openSettings
        default: nil
        }
    }

    /// Badges sit beside the name and widen the whole menu, so problems get a few words here;
    /// the full ``ProfileState/message`` is the row's tooltip.
    private static func shortProblem(_ state: ProfileState) -> String? {
        switch state {
        case .notLoaded, .fresh: nil
        case .stale(.claude): "Open Claude Code"
        case .stale(.codex): "Sign in again"
        case .rateLimited: "Rate limited"
        case .error: "Refresh failed"
        case .unsupportedResponse: "Update needed"
        case .keychainDenied: "Needs Keychain access"
        case .keychainItemNotFound: "Keychain item missing"
        case .credentialsNotFound: "No credentials"
        case .apiKeyMode: "API key mode"
        }
    }

    private static func summary(_ windows: [UsageWindow], state: ProfileState, now: Date) -> String {
        guard !windows.isEmpty else {
            return state == .notLoaded ? "Loading…" : "No usage data"
        }
        return windows.map { window in
            let used = "\(window.label) \(Int(window.usedPercent.rounded(.down)))%"
            guard let resetsAt = window.resetsAt else {
                return used
            }
            return "\(used) (\(CompactDuration.format(resetsAt.timeIntervalSince(now))))"
        }
        .joined(separator: separator)
    }
}
