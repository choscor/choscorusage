// Finds Claude and Codex config directories in the home directory and the environment.
import ChoscorUsageCore
import Foundation

/// Scans for profile candidates. Reads directory listings and Keychain attributes only; never
/// reads credentials or item data, so it never triggers a Keychain prompt.
public struct ProfileDiscovery: Sendable {
    private static let claudeMarkers = [".credentials.json", "settings.json", "projects"]
    // Credential and settings files identify a provider; `projects`, `sessions` and
    // `config.toml` are generic enough to appear in unrelated folders, so they only break ties.
    private static let strongMarkers: [Provider: [String]] = [
        .claude: [".credentials.json", "settings.json"], .codex: ["auth.json"],
    ]
    private static let weakMarkers: [Provider: [String]] = [
        .claude: ["projects"], .codex: ["config.toml", "sessions"],
    ]

    private let fileSystem: any FileSystem

    /// Creates a discovery over `fileSystem`.
    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    /// Returns candidates in order: Claude (`~/.claude`, marked or Keychain-backed `~/.claude*`,
    /// `CLAUDE_CONFIG_DIR`), then Codex (`~/.codex`, `~/.codex*` with `auth.json`, `CODEX_HOME`).
    /// Paths already in `existing`, or found twice, are compared after standardization and skipped.
    public func discover(
        home: String, environment: any EnvironmentReading, keychain: any KeychainReading, existing: [Profile]
    ) -> [DiscoveredProfile] {
        let services = Set((try? keychain.serviceNames(withPrefix: ClaudeKeychainService.defaultName)) ?? [])
        let entries = fileSystem.directoryEntries(atPath: home).sorted()
        var claude = entries.filter { $0.hasPrefix(".claude") }.map { "\(home)/\($0)" }.filter { path in
            path == "\(home)/.claude" && fileSystem.isDirectory(atPath: path)
                || hasClaudeMarker(path)
                || ClaudeKeychainService.candidates(forConfigDir: path, home: home).contains(where: services.contains)
        }
        claude += [environment.value(forKey: "CLAUDE_CONFIG_DIR")].compactMap { $0 }
        var codex = entries.filter { $0.hasPrefix(".codex") }.map { "\(home)/\($0)" }.filter { path in
            path == "\(home)/.codex" || fileSystem.fileExists(atPath: "\(path)/auth.json")
        }
        codex += [environment.value(forKey: "CODEX_HOME")].compactMap { $0 }

        var seen = Set(existing.map { ConfigPath.standardized($0.configDirectory, home: home) })
        let candidates = claude.map { (Provider.claude, $0) } + codex.map { (Provider.codex, $0) }
        return candidates.compactMap { provider, path in
            let standard = ConfigPath.standardized(path, home: home)
            guard fileSystem.isDirectory(atPath: standard), seen.insert(standard).inserted else {
                return nil
            }
            let name = Self.defaultDisplayName(
                provider: provider, directoryName: ConfigPath.lastComponent(of: path, home: home))
            return DiscoveredProfile(provider: provider, configDirectory: path, displayName: name)
        }
    }

    /// Derives a display name: `.claude-03` → `Claude · 03`, `.claude` → `Claude`,
    /// `claude-cfg` → `Claude · cfg`, `team-settings` → `Claude · team-settings`.
    public static func defaultDisplayName(provider: Provider, directoryName: String) -> String {
        var rest = Substring(directoryName)
        if rest.hasPrefix(".") {
            rest = rest.dropFirst()
        }
        if rest.lowercased().hasPrefix(provider.rawValue) {
            rest = rest.dropFirst(provider.rawValue.count)
        }
        let suffix = rest.trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        return suffix.isEmpty ? provider.displayName : "\(provider.displayName) · \(suffix)"
    }

    /// Detects which CLI owns the directory at `path` (standardized, absolute). The first rule
    /// that names exactly one provider wins: credential or settings files, then generic folders,
    /// then a folder name containing `claude` or `codex`. Returns `nil` for the home folder, a
    /// missing directory or no clear answer. Reads directory metadata only; call off the main actor.
    public func provider(forDirectory path: String) -> Provider? {
        let home = ConfigPath.standardized(fileSystem.homeDirectory, home: fileSystem.homeDirectory)
        guard path != home, fileSystem.isDirectory(atPath: path) else {
            return nil
        }
        let name = (path.split(separator: "/").last ?? "").lowercased()
        let rules: [(Provider) -> Bool] = [
            { hasMarker(Self.strongMarkers[$0] ?? [], in: path) },
            { hasMarker(Self.weakMarkers[$0] ?? [], in: path) },
            { name.contains($0.rawValue) },
        ]
        for rule in rules {
            let matches = Provider.allCases.filter(rule)
            if matches.count == 1 {
                return matches.first
            }
        }
        return nil
    }

    private func hasMarker(_ markers: [String], in path: String) -> Bool {
        markers.contains { fileSystem.fileExists(atPath: "\(path)/\($0)") }
    }

    private func hasClaudeMarker(_ path: String) -> Bool {
        fileSystem.isDirectory(atPath: path)
            && Self.claudeMarkers.contains { fileSystem.fileExists(atPath: "\(path)/\($0)") }
    }
}
