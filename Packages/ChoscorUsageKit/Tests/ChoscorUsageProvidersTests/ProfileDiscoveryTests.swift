// Tests auto-discovery of Claude and Codex config directories without duplicates.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct ProfileDiscoveryTests {
    private let home: TemporaryHome
    private let keychain = FakeKeychain()

    init() throws {
        home = try TemporaryHome()
    }

    private func discover(_ environment: [String: String] = [:], existing: [Profile] = []) -> [DiscoveredProfile] {
        ProfileDiscovery(fileSystem: LocalFileSystem(homeDirectory: home.path))
            .discover(
                home: home.path, environment: FakeEnvironment(environment), keychain: keychain, existing: existing)
    }

    private func names(_ found: [DiscoveredProfile]) -> [String] {
        found.map { "\($0.provider.rawValue):\(($0.configDirectory as NSString).lastPathComponent)" }
    }

    @Test func findsMarkedClaudeAndCodexDirectoriesAndSkipsUnmarkedOnesAndFiles() throws {
        try home.makeDirectory(".claude")
        try home.write(".claude-03/.credentials.json", "{}")
        try home.write(".claude-work/settings.json", "{}")
        try home.makeDirectory(".claude-personal/projects")
        try home.makeDirectory(".claude-empty")
        try home.write(".claude.json", "{}")
        try home.makeDirectory(".codex")
        try home.write(".codex-team/auth.json", "{}")
        try home.makeDirectory(".codex-cache")
        #expect(
            names(discover()) == [
                "claude:.claude", "claude:.claude-03", "claude:.claude-personal", "claude:.claude-work",
                "codex:.codex", "codex:.codex-team",
            ])
    }

    @Test func directoryWhoseCredentialsLiveOnlyInTheKeychainIsFound() throws {
        try home.makeDirectory(".claude-keychain-only")
        keychain.set(ClaudeKeychainService.name(forConfigDir: "\(home.path)/.claude-keychain-only"), .success(Data()))
        #expect(names(discover()) == ["claude:.claude-keychain-only"])
        #expect(keychain.reads.isEmpty, "discovery lists attributes only and never reads item data")
    }

    @Test func environmentDirectoriesAreAddedOnceEvenWhenSpelledDifferently() throws {
        try home.write(".claude-03/.credentials.json", "{}")
        try home.write("elsewhere/claude-cfg/settings.json", "{}")
        try home.write("elsewhere/codex-home/auth.json", "{}")
        let found = discover([
            "CLAUDE_CONFIG_DIR": "\(home.path)/elsewhere/claude-cfg/",
            "CODEX_HOME": "\(home.path)/elsewhere/codex-home",
        ])
        #expect(names(found) == ["claude:.claude-03", "claude:claude-cfg", "codex:codex-home"])
        try #require(found.count == 3)
        #expect(found[1].configDirectory == "\(home.path)/elsewhere/claude-cfg/")
        let again = discover(["CLAUDE_CONFIG_DIR": "\(home.path)/.claude-03/"])
        #expect(names(again) == ["claude:.claude-03"])
    }

    @Test func alreadyTrackedDirectoriesAreNotOfferedAgain() throws {
        try home.write(".claude-03/.credentials.json", "{}")
        try home.makeDirectory(".codex")
        let tracked = Profile(
            provider: .claude, configDirectory: "\(home.path)/.claude-03/", displayName: "Mine", order: 0)
        #expect(names(discover(existing: [tracked])) == ["codex:.codex"])
    }

    @Test(arguments: [
        (".claude", "Claude"), (".claude-03", "Claude · 03"), (".claude_work", "Claude · work"),
        (".codex", "Codex"), (".codex-personal", "Codex · personal"), ("claude-cfg", "Claude · cfg"),
        ("team-settings", "Claude · team-settings"),
    ])
    func defaultDisplayNamesComeFromTheDirectoryName(directory: String, expected: String) {
        let provider: Provider = directory.contains("codex") ? .codex : .claude
        #expect(ProfileDiscovery.defaultDisplayName(provider: provider, directoryName: directory) == expected)
    }
}
