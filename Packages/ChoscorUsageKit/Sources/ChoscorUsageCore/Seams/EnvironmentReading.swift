// The injectable process-environment seam (named to avoid SwiftUI's `Environment`).

/// Reads environment variables such as `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.
public protocol EnvironmentReading: Sendable {
    /// Returns the variable's value, or `nil` when it is unset or empty.
    func value(forKey key: String) -> String?
}
