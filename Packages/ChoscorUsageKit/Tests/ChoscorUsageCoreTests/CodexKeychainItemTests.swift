// Tests the Codex CLI's Keychain item naming for keyring-stored credentials.
import Testing

@testable import ChoscorUsageCore

struct CodexKeychainItemTests {
    @Test func accountIsCliAndTheFirstSixteenHexCharactersOfTheHomeSHA256() {
        // Expected value computed with `printf '%s' /Users/x/.codex | shasum -a 256`.
        let item = CodexKeychainItem(codexHome: "/Users/x/.codex", home: "/Users/x")
        #expect(item.service == "Codex Auth")
        #expect(item.account == "cli|3b125282c29110fe")
    }

    @Test func homeIsStandardizedBeforeHashing() {
        let tilde = CodexKeychainItem(codexHome: "~/.codex/", home: "/Users/x")
        #expect(tilde.account == "cli|3b125282c29110fe")
    }
}
