// The CLI whose subscription limits a profile tracks.

/// The command-line tool a profile belongs to.
public enum Provider: String, Codable, CaseIterable, Sendable {
    /// Claude Code (`claude`), signed in with a Pro or Max plan.
    case claude
    /// Codex CLI (`codex`), signed in with a ChatGPT plan.
    case codex

    /// Human-readable provider name used in default display names.
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// The command users run to sign in again when a token is stale.
    public var signInCommand: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex login"
        }
    }
}
