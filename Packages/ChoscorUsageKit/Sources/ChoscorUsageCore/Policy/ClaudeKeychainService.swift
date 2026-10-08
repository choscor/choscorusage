// Derives the macOS Keychain service names Claude Code uses for a config directory.
import CryptoKit
import Foundation

/// Claude Code's Keychain naming rule, observed rather than documented.
///
/// The default config directory (`~/.claude` without `CLAUDE_CONFIG_DIR`) stores its OAuth
/// credentials under the generic-password service `Claude Code-credentials`. Any other
/// directory appends `-` and the first 8 lowercase hex characters of SHA-256 over the
/// NFC-normalized UTF-8 config-dir string, hashed exactly as given (no tilde expansion, no
/// trailing-slash normalization). Verified against 5 of 6 local profiles on 2026-10-08;
/// see https://github.com/steipete/CodexBar/blob/main/docs/claude.md.
public enum ClaudeKeychainService {
    /// The service name used by the default `~/.claude` profile.
    public static let defaultName = "Claude Code-credentials"

    /// Returns the service name for `configDir`, or ``defaultName`` when it is `nil`.
    public static func name(forConfigDir configDir: String?) -> String {
        guard let configDir else {
            return defaultName
        }
        let normalized = Data(configDir.precomposedStringWithCanonicalMapping.utf8)
        let digest = SHA256.hash(data: normalized)
        let prefix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(defaultName)-\(prefix)"
    }

    /// Returns the service names to try, in order, for a profile stored as `configDir`.
    ///
    /// The default directory tries ``defaultName`` first. Every directory then tries the hash
    /// of its spelling without and with a trailing slash; no other spellings are guessed.
    public static func candidates(forConfigDir configDir: String, home: String) -> [String] {
        let standard = ConfigPath.standardized(configDir, home: home)
        let isDefault = standard == ConfigPath.standardized("~/.claude", home: home)
        let bare = configDir.hasSuffix("/") ? String(configDir.dropLast()) : configDir
        var names = isDefault ? [defaultName] : []
        for spelling in [bare, bare + "/"] where !names.contains(name(forConfigDir: spelling)) {
            names.append(name(forConfigDir: spelling))
        }
        return names
    }
}
