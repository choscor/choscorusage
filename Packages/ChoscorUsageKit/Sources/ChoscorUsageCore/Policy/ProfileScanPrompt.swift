// Builds the confirmation shown after a profile scan, and the menu item that reopens it.

/// The text that asks the user to confirm discovered profiles; nothing is added until they do.
public struct ProfileScanPrompt: Equatable, Sendable {
    /// The alert's headline.
    public let title: String
    /// The alert's body: one line per candidate, or where the scan looked when it found none.
    public let message: String
    /// The confirming button's title, or `nil` when there is nothing to add.
    public let confirmTitle: String?
    /// The menu item that reopens the prompt, or `nil` when there is nothing to add.
    public let menuTitle: String?

    /// Builds the prompt for `candidates` in discovery order. Pure; any thread.
    public static func make(for candidates: [DiscoveredProfile]) -> Self {
        guard !candidates.isEmpty else {
            return Self(
                title: "No New Profiles Found",
                message: "ChoscorUsage looks for ~/.claude* and ~/.codex* folders, CLAUDE_CONFIG_DIR and CODEX_HOME. "
                    + "Use Add Profile to choose a folder yourself.",
                confirmTitle: nil,
                menuTitle: nil)
        }
        let count = candidates.count
        let noun = count == 1 ? "Profile" : "Profiles"
        return Self(
            title: "Found \(count) New \(noun)",
            message: candidates.map { "\($0.displayName) — \($0.configDirectory)" }.joined(separator: "\n"),
            confirmTitle: count == 1 ? "Add Profile" : "Add \(count) Profiles",
            menuTitle: "Review \(count) Found \(noun)…")
    }
}
