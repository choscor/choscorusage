// Fetches Codex usage with the CLI's token, falling back to local session logs.
import ChoscorUsageCore

/// Codex usage via the ChatGPT backend, with the session-log fallback for network errors, 5xx
/// and undecodable responses. 401/403, 429 and API-key mode never use the fallback.
public struct CodexUsageProvider: UsageProviding {
    private let fileSystem: any FileSystem
    private let keychain: any KeychainReading
    private let transport: any HTTPTransport
    private let clock: any WallClock
    private let userAgent: String

    /// Creates a provider. `userAgent` is `ChoscorUsage/<version>`.
    public init(
        fileSystem: any FileSystem, keychain: any KeychainReading, transport: any HTTPTransport, clock: any WallClock,
        userAgent: String
    ) {
        self.fileSystem = fileSystem
        self.keychain = keychain
        self.transport = transport
        self.clock = clock
        self.userAgent = userAgent
    }

    /// Reads `auth.json` (or the keyring item), requests usage once, and maps the result.
    /// `allowingPrompt` changes nothing: Codex has one credential read path.
    public func fetch(_ profile: Profile, allowingPrompt _: Bool) async -> UsageFetchOutcome {
        let token: String
        let accountID: String?
        let credentials = CodexCredentials.read(
            configDirectory: profile.configDirectory, fileSystem: fileSystem, keychain: keychain)
        switch credentials {
        case .notFound:
            return .credentialsNotFound
        case .keychainDenied:
            return .keychainDenied
        case .apiKeyMode:
            return .apiKeyMode
        case .chatGPT(let accessToken, let account):
            (token, accountID) = (accessToken, account)
        }
        guard let url = CodexEndpoint.usageURL(configDirectory: profile.configDirectory, fileSystem: fileSystem) else {
            return .failed(detail: "Invalid chatgpt_base_url in config.toml", fallback: nil)
        }
        var headers = ["Authorization": "Bearer \(token)", "User-Agent": userAgent, "Accept": "application/json"]
        headers["ChatGPT-Account-Id"] = accountID
        guard let response = try? await transport.send(HTTPRequest(url: url, headers: headers)) else {
            return .failed(detail: "Couldn't reach Codex", fallback: fallback(for: profile))
        }
        switch response.statusCode {
        case 200..<300:
            guard let windows = try? CodexUsageDecoder.decode(response.body, now: clock.now) else {
                return .unsupportedResponse(fallback: fallback(for: profile))
            }
            return .success(UsageSnapshot(windows: windows, fetchedAt: clock.now, source: .endpoint))
        case 500..<600:
            return .failed(detail: "Codex returned HTTP \(response.statusCode)", fallback: fallback(for: profile))
        default:
            return HTTPStatusOutcome.outcome(forStatus: response.statusCode, providerName: "Codex")
        }
    }

    private func fallback(for profile: Profile) -> UsageSnapshot? {
        CodexSessionLogReader(fileSystem: fileSystem).latestSnapshot(
            configDirectory: profile.configDirectory, now: clock.now)
    }
}
