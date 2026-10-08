// Tests the Claude Code keychain service-name rule for default and custom config dirs.
import Testing

@testable import ChoscorUsageCore

struct ClaudeKeychainServiceTests {
    @Test func defaultDirectoryUsesTheUnsuffixedService() {
        #expect(ClaudeKeychainService.name(forConfigDir: nil) == "Claude Code-credentials")
    }

    @Test func customDirectoryAppendsTheFirstEightHexCharactersOfItsSHA256() {
        // Expected prefix computed with `printf '%s' /Users/x/.claude-01 | shasum -a 256`.
        #expect(ClaudeKeychainService.name(forConfigDir: "/Users/x/.claude-01") == "Claude Code-credentials-2cbb5ea8")
    }

    @Test func pathIsHashedExactlyAsGivenWithoutTrailingSlashNormalization() {
        #expect(ClaudeKeychainService.name(forConfigDir: "/Users/x/.claude-01/") == "Claude Code-credentials-2f6d6d5b")
    }

    @Test func canonicallyEquivalentSpellingsGiveTheSameName() {
        let composed = "/Users/x/.claude-caf\u{00E9}"
        let decomposed = "/Users/x/.claude-cafe\u{0301}"
        #expect(ClaudeKeychainService.name(forConfigDir: decomposed) == "Claude Code-credentials-b487dea8")
        #expect(ClaudeKeychainService.name(forConfigDir: composed) == "Claude Code-credentials-b487dea8")
    }

    @Test func defaultProfileTriesTheUnsuffixedServiceFirst() {
        let names = ClaudeKeychainService.candidates(forConfigDir: "/Users/x/.claude", home: "/Users/x")
        #expect(names.first == "Claude Code-credentials")
    }

    @Test func customProfileAlsoTriesTheTrailingSlashSpelling() {
        let names = ClaudeKeychainService.candidates(forConfigDir: "/Users/x/.claude-01", home: "/Users/x")
        #expect(names == ["Claude Code-credentials-2cbb5ea8", "Claude Code-credentials-2f6d6d5b"])
    }
}
