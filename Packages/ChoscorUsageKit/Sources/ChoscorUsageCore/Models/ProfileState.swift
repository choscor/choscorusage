// The health of a profile's most recent refresh attempt.
import Foundation

/// Outcome of the latest refresh for a profile; last good data is kept separately.
public enum ProfileState: Equatable, Sendable {
    /// Not refreshed since launch.
    case notLoaded
    /// The latest refresh succeeded.
    case fresh
    /// The token is expired or rejected; running the CLI in the profile renews it, and the next
    /// refresh picks the new token up.
    case stale(Provider)
    /// The provider returned 429; automatic refreshes wait until `retryAt`.
    case rateLimited(retryAt: Date)
    /// A network error or 5xx response; `detail` is safe to display.
    case error(detail: String)
    /// The response no longer matches the decoder.
    case unsupportedResponse
    /// The user denied Keychain access; only an explicit Retry prompts again.
    case keychainDenied
    /// None of the computed Claude Keychain services exist and there is no credentials file.
    case keychainItemNotFound
    /// No credentials file exists in the config directory.
    case credentialsNotFound
    /// Codex is signed in with an API key, which has no plan limits.
    case apiKeyMode

    /// The inline message shown for this state, or `nil` when the profile is healthy.
    public var message: String? {
        switch self {
        case .notLoaded, .fresh: nil
        // The user is still signed in: Claude Code renews its short-lived access token only while
        // it runs, and ChoscorUsage must never call the refresh endpoint itself. Renewing rewrites
        // the Keychain item, so macOS may ask again before ChoscorUsage can read the new token.
        case .stale(.claude):
            "Access token expired. Open Claude Code with this profile to renew it, "
                + "then allow Keychain access if macOS asks."
        case .stale(.codex): "Run `codex login` in this profile."
        case .rateLimited: "Rate limited – retrying later"
        case .error(let detail): detail
        case .unsupportedResponse: "Usage format changed – update ChoscorUsage"
        case .keychainDenied: "Keychain access needed"
        case .keychainItemNotFound: "Keychain item not found"
        case .credentialsNotFound: "No credentials found in this directory"
        case .apiKeyMode: "API key mode – no plan limits"
        }
    }
}

extension ProfileState {
    /// A stable, detail-free name for diagnostics; never includes server text.
    public var kind: String {
        switch self {
        case .notLoaded: "notLoaded"
        case .fresh: "fresh"
        case .stale: "stale"
        case .rateLimited: "rateLimited"
        case .error: "error"
        case .unsupportedResponse: "unsupportedResponse"
        case .keychainDenied: "keychainDenied"
        case .keychainItemNotFound: "keychainItemNotFound"
        case .credentialsNotFound: "credentialsNotFound"
        case .apiKeyMode: "apiKeyMode"
        }
    }
}
