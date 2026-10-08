// The result of one usage fetch for one profile, before refresh bookkeeping.

/// What a provider learned in one attempt. Kit turns this into a ``ProfileState`` and keeps
/// last good data on failure.
public enum UsageFetchOutcome: Equatable, Sendable {
    /// Fresh windows.
    case success(UsageSnapshot)
    /// Token expired (no request made) or rejected with 401/403.
    case stale
    /// HTTP 429.
    case rateLimited
    /// Transport error or 5xx; `fallback` holds Codex local-log data when available.
    case failed(detail: String, fallback: UsageSnapshot?)
    /// The response could not be decoded; `fallback` holds Codex local-log data when available.
    case unsupportedResponse(fallback: UsageSnapshot?)
    /// The user denied Keychain access.
    case keychainDenied
    /// No Claude Keychain item or credentials file.
    case keychainItemNotFound
    /// No Codex `auth.json`.
    case credentialsNotFound
    /// Codex is in API-key mode, which has no plan limits.
    case apiKeyMode
}
