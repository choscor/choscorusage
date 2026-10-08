// The shortest time between two usage requests for one profile, per provider.

/// Per-provider floors applied on top of the user's refresh interval.
public enum FetchSpacing {
    /// Claude's usage endpoint answers bursts with 429s that can last up to an hour, and Claude
    /// Code's own `/usage` view draws on the same limit, so one Claude profile is fetched at most
    /// every 3 minutes (https://github.com/anthropics/claude-code/issues/30930 and
    /// https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/claude/README.md, verified
    /// 2026-10-08). Codex has no reported limit and keeps no floor.
    public static let live: [Provider: Duration] = [.claude: .seconds(180)]
}
