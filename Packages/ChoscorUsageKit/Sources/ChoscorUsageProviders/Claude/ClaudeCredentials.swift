// The two credential fields the app uses from Claude Code's OAuth record.
import Foundation

/// A Claude OAuth access token and its expiry. The refresh token is never read into memory.
public struct ClaudeCredentials: Equatable, Sendable {
    /// Bearer token for the usage endpoint; never logged or persisted.
    public let accessToken: String
    /// When the access token expires, if recorded.
    public let expiresAt: Date?

    /// Creates credentials.
    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

/// The outcome of looking up a profile's Claude credentials.
public enum ClaudeCredentialResult: Equatable, Sendable {
    /// Credentials were found in the Keychain or the credentials file.
    case found(ClaudeCredentials)
    /// The user denied Keychain access; nothing else was tried.
    case keychainDenied
    /// No Keychain item and no `.credentials.json`.
    case notFound
    /// The Keychain could not be read (e.g. locked before first unlock) and the credentials
    /// file has no token; transient, so it is retried on the next refresh.
    case keychainUnavailable

    /// The access token when found.
    public var accessToken: String? {
        if case .found(let credentials) = self {
            return credentials.accessToken
        }
        return nil
    }
}
