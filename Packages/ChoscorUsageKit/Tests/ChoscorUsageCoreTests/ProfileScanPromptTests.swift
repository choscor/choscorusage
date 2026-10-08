// Tests the confirmation text shown after scanning for profiles.
import Testing

@testable import ChoscorUsageCore

struct ProfileScanPromptTests {
    private let work = DiscoveredProfile(
        provider: .claude, configDirectory: "~/.claude-work", displayName: "Claude · work")
    private let codex = DiscoveredProfile(provider: .codex, configDirectory: "~/.codex", displayName: "Codex")

    @Test func listsEveryCandidateAndOffersToAddThemAll() {
        let prompt = ProfileScanPrompt.make(for: [work, codex])
        #expect(prompt.title == "Found 2 New Profiles")
        #expect(prompt.message == "Claude · work — ~/.claude-work\nCodex — ~/.codex")
        #expect(prompt.confirmTitle == "Add 2 Profiles")
        #expect(prompt.menuTitle == "Review 2 Found Profiles…")
    }

    @Test func singleCandidateIsSingular() {
        let prompt = ProfileScanPrompt.make(for: [codex])
        #expect(prompt.title == "Found 1 New Profile")
        #expect(prompt.confirmTitle == "Add Profile")
        #expect(prompt.menuTitle == "Review 1 Found Profile…")
    }

    @Test func noCandidatesSaysWhereTheScanLooked() {
        let prompt = ProfileScanPrompt.make(for: [])
        #expect(prompt.title == "No New Profiles Found")
        for place in ["~/.claude*", "~/.codex*", "CLAUDE_CONFIG_DIR", "CODEX_HOME", "Add Profile"] {
            #expect(prompt.message.contains(place))
        }
        #expect(prompt.confirmTitle == nil)
        #expect(prompt.menuTitle == nil)
    }
}
