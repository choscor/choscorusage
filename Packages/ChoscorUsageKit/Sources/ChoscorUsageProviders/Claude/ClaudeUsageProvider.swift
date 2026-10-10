// Fetches Claude usage for a profile with its existing OAuth token.
import ChoscorUsageCore
import Foundation

/// Claude Code usage via `GET https://api.anthropic.com/api/oauth/usage`.
///
/// The endpoint and its `anthropic-beta: oauth-2025-04-20` header are undocumented; source:
/// https://github.com/steipete/CodexBar/blob/main/docs/claude.md (verified 2026-10-08).
public struct ClaudeUsageProvider: UsageProviding {
    private enum TokenLookup {
        case token(String)
        case outcome(UsageFetchOutcome)
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentials: ClaudeCredentialReader
    private let transport: any HTTPTransport
    private let clock: any WallClock
    private let userAgent: String
    private let cache = ClaudeCredentialCache()

    /// Creates a provider. `userAgent` is `ChoscorUsage/<version>`.
    public init(
        credentials: ClaudeCredentialReader, transport: any HTTPTransport, clock: any WallClock, userAgent: String
    ) {
        self.credentials = credentials
        self.transport = transport
        self.clock = clock
        self.userAgent = userAgent
    }

    /// Uses the token cached in memory while it is unexpired; otherwise reads credentials once
    /// (falling back to a direct Keychain read only when `allowingPrompt`), skips the request
    /// for an expired token, then fetches and decodes. A 401 or 403 drops the cached token.
    public func fetch(_ profile: Profile, allowingPrompt: Bool) async -> UsageFetchOutcome {
        let token: String
        switch lookUpToken(for: profile, allowingPrompt: allowingPrompt) {
        case .token(let found):
            token = found
        case .outcome(let outcome):
            return outcome
        }
        let request = HTTPRequest(
            url: Self.endpoint,
            headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": userAgent,
                "Accept": "application/json",
            ])
        guard let response = try? await transport.send(request) else {
            return .failed(detail: "Couldn't reach Claude", fallback: nil)
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                cache.discard(profile.id)
            }
            return HTTPStatusOutcome.outcome(forStatus: response.statusCode, providerName: "Claude")
        }
        guard let windows = try? ClaudeUsageDecoder.decode(response.body, now: clock.now) else {
            return .unsupportedResponse(fallback: nil)
        }
        return .success(UsageSnapshot(windows: windows, fetchedAt: clock.now, source: .endpoint))
    }

    /// Drops the token cached for `profileID`. Any thread.
    public func discardCachedCredentials(for profileID: UUID) {
        cache.discard(profileID)
    }

    private func lookUpToken(for profile: Profile, allowingPrompt: Bool) -> TokenLookup {
        let now = clock.now
        if let cached = cache.credentials(for: profile, now: now) {
            return .token(cached.accessToken)
        }
        switch credentials.read(for: profile, allowingDirectRead: allowingPrompt) {
        case .keychainDenied:
            return .outcome(.keychainDenied)
        case .notFound:
            return .outcome(.keychainItemNotFound)
        case .keychainUnavailable:
            return .outcome(.failed(detail: "Keychain is locked or unavailable", fallback: nil))
        case .found(let found):
            if let expiresAt = found.expiresAt, expiresAt <= now {
                return .outcome(.stale)
            }
            cache.store(found, for: profile)
            return .token(found.accessToken)
        }
    }
}
