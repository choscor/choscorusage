// Fetches Claude usage for a profile with its existing OAuth token.
import ChoscorUsageCore
import Foundation

/// Claude Code usage via `GET https://api.anthropic.com/api/oauth/usage`.
///
/// The endpoint and its `anthropic-beta: oauth-2025-04-20` header are undocumented; source:
/// https://github.com/steipete/CodexBar/blob/main/docs/claude.md (verified 2026-10-08).
public struct ClaudeUsageProvider: UsageProviding {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentials: ClaudeCredentialReader
    private let transport: any HTTPTransport
    private let clock: any WallClock
    private let userAgent: String

    /// Creates a provider. `userAgent` is `ChoscorUsage/<version>`.
    public init(
        credentials: ClaudeCredentialReader, transport: any HTTPTransport, clock: any WallClock, userAgent: String
    ) {
        self.credentials = credentials
        self.transport = transport
        self.clock = clock
        self.userAgent = userAgent
    }

    /// Reads credentials once, skips the request for an expired token, then fetches and decodes.
    public func fetch(_ profile: Profile) async -> UsageFetchOutcome {
        let token: String
        switch credentials.read(for: profile) {
        case .keychainDenied:
            return .keychainDenied
        case .notFound:
            return .keychainItemNotFound
        case .keychainUnavailable:
            return .failed(detail: "Keychain is locked or unavailable", fallback: nil)
        case .found(let found):
            if let expiresAt = found.expiresAt, expiresAt <= clock.now {
                return .stale
            }
            token = found.accessToken
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
            return HTTPStatusOutcome.outcome(forStatus: response.statusCode, providerName: "Claude")
        }
        guard let windows = try? ClaudeUsageDecoder.decode(response.body, now: clock.now) else {
            return .unsupportedResponse(fallback: nil)
        }
        return .success(UsageSnapshot(windows: windows, fetchedAt: clock.now, source: .endpoint))
    }
}
