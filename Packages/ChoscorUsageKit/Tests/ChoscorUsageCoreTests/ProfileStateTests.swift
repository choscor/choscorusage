// Pins the inline messages shown for each non-fresh profile state.
import Testing

@testable import ChoscorUsageCore

struct ProfileStateTests {
    @Test(arguments: [
        (ProfileState.stale(.claude), "Token expired. Run `claude` in this profile to refresh."),
        (.stale(.codex), "Run `codex login` in this profile."),
        (.apiKeyMode, "API key mode – no plan limits"),
        (.unsupportedResponse, "Usage format changed – update ChoscorUsage"),
        (.keychainDenied, "Keychain access needed"),
        (.keychainItemNotFound, "Keychain item not found"),
        (.error(detail: "Couldn't reach Claude"), "Couldn't reach Claude"),
    ])
    func nonFreshStatesShowTheSpecifiedMessage(state: ProfileState, message: String) {
        #expect(state.message == message)
    }

    @Test func freshAndUnloadedProfilesShowNoMessage() {
        #expect(ProfileState.fresh.message == nil)
        #expect(ProfileState.notLoaded.message == nil)
    }
}
