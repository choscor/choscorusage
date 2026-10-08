// Resolves the Codex usage URL, honoring `chatgpt_base_url` in config.toml.
import ChoscorUsageCore
import Foundation

/// The usage URL for a Codex config directory.
///
/// Mirrors the CLI's path rule as documented by CodexBar (verified 2026-10-08): bases containing
/// `/backend-api` use `/wham/usage`, other bases `/api/codex/usage`. A single key lookup is enough,
/// so there is no TOML parser.
internal enum CodexEndpoint {
    private static let defaultBase = "https://chatgpt.com/backend-api"

    /// Returns the usage URL for `configDirectory`.
    internal static func usageURL(configDirectory: String, fileSystem: any FileSystem) -> URL? {
        let directory = ConfigPath.standardized(configDirectory, home: fileSystem.homeDirectory)
        let config = fileSystem.contents(atPath: "\(directory)/config.toml").flatMap {
            String(bytes: $0, encoding: .utf8)
        }
        var base = config.flatMap(baseURL(inConfig:)) ?? defaultBase
        while base.hasSuffix("/") {
            base.removeLast()
        }
        let isChatGPTHost = base.hasPrefix("https://chatgpt.com") || base.hasPrefix("https://chat.openai.com")
        if isChatGPTHost && !base.contains("/backend-api") {
            base += "/backend-api"
        }
        return URL(string: base + (base.contains("/backend-api") ? "/wham/usage" : "/api/codex/usage"))
    }

    /// Returns the first active `chatgpt_base_url = "…"` value, ignoring comments.
    internal static func baseURL(inConfig contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "chatgpt_base_url" else {
                continue
            }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
