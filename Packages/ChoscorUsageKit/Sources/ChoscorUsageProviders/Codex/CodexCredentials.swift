// Reads the Codex CLI's auth.json, or its keyring item, for the token and account ID, read-only.
import ChoscorUsageCore
import Foundation

/// The outcome of reading `<config-dir>/auth.json` or the matching ``CodexKeychainItem``.
public enum CodexCredentials: Equatable, Sendable {
    /// ChatGPT sign-in with an access token and account ID; neither is ever logged.
    case chatGPT(accessToken: String, accountID: String?)
    /// API-key sign-in (or no `tokens`), which has no plan limits.
    case apiKeyMode
    /// No readable `auth.json` and no keyring item.
    case notFound
    /// The user denied access to the keyring item; only an explicit Retry reads it again.
    case keychainDenied

    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String?
            let accountId: String?
        }

        let authMode: String?
        let tokens: Tokens?
    }

    /// Reads `auth.json` under `configDirectory`; only when it is missing reads the keyring item,
    /// which holds the same JSON, so file-mode users never see a Keychain prompt. `auth_mode`
    /// values follow the CLI's `AuthMode` serialization (`apikey`, `chatgpt`; see openai/codex
    /// `codex-rs/protocol/src/auth.rs`, verified 2026-10-08). Never refreshes or rewrites either.
    /// May block on a Keychain prompt; call it off the main actor.
    public static func read(
        configDirectory: String, fileSystem: any FileSystem, keychain: any KeychainReading
    ) -> Self {
        let directory = ConfigPath.standardized(configDirectory, home: fileSystem.homeDirectory)
        if let data = fileSystem.contents(atPath: "\(directory)/auth.json") {
            return decode(data)
        }
        let item = CodexKeychainItem(codexHome: configDirectory, home: fileSystem.homeDirectory)
        do {
            guard let data = try keychain.genericPassword(service: item.service, account: item.account) else {
                return .notFound
            }
            return decode(data)
        } catch .denied {
            return .keychainDenied
        } catch {
            return .notFound
        }
    }

    private static func decode(_ data: Data) -> Self {
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
