// Derives the Keychain item the Codex CLI uses when it stores credentials in the OS keyring.
import CryptoKit
import Foundation

/// The generic-password item holding a Codex home's `auth.json` contents in keyring mode.
///
/// With `cli_auth_credentials_store = "keyring"` (or `"auto"` when a keyring is available) Codex
/// stores the serialized `auth.json` under service `Codex Auth` and account
/// `cli|<first 16 hex chars of SHA-256 over the canonical CODEX_HOME path>`. Source:
/// https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs (`KEYRING_SERVICE`,
/// `compute_store_key`), verified 2026-10-08. Codex canonicalizes with symlink resolution; this
/// standardizes the spelling only, so a symlinked CODEX_HOME will not match.
public struct CodexKeychainItem: Equatable, Sendable {
    /// Always `Codex Auth`.
    public let service = "Codex Auth"
    /// `cli|<16 hex>` for the home directory.
    public let account: String

    /// Creates the item for `codexHome`, expanding `~` against `home`. Pure; any thread.
    public init(codexHome: String, home: String) {
        let canonical = ConfigPath.standardized(codexHome, home: home)
        let digest = SHA256.hash(data: Data(canonical.utf8))
        account = "cli|" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
