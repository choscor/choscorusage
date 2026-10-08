// Reads the Codex CLI's auth.json for the token and account ID, read-only.
import ChoscorUsageCore
import Foundation

/// The outcome of reading `<config-dir>/auth.json`.
public enum CodexCredentials: Equatable, Sendable {
    /// ChatGPT sign-in with an access token and account ID; neither is ever logged.
    case chatGPT(accessToken: String, accountID: String?)
    /// API-key sign-in (or no `tokens`), which has no plan limits.
    case apiKeyMode
    /// No readable `auth.json`.
    case notFound

    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String?
            let accountId: String?
        }

        let authMode: String?
        let tokens: Tokens?
    }

    /// Reads `auth.json` under `configDirectory`. `auth_mode` values follow the CLI's `AuthMode`
    /// serialization (`apikey`, `chatgpt`; see openai/codex `codex-rs/protocol/src/auth.rs`,
    /// verified 2026-10-08). Never refreshes or rewrites the file.
    public static func read(configDirectory: String, fileSystem: any FileSystem) -> Self {
        let directory = ConfigPath.standardized(configDirectory, home: fileSystem.homeDirectory)
        guard let data = fileSystem.contents(atPath: "\(directory)/auth.json") else {
            return .notFound
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let file = try? decoder.decode(AuthFile.self, from: data) else {
            return .notFound
        }
        guard file.authMode?.lowercased() != "apikey", let token = file.tokens?.accessToken, !token.isEmpty else {
            return .apiKeyMode
        }
        return .chatGPT(accessToken: token, accountID: file.tokens?.accountId)
    }
}
