// Tests how Security framework statuses map to Keychain errors.
import ChoscorUsageCore
import Security
import Testing

@testable import ChoscorUsageProviders

struct KeychainStatusTests {
    @Test(arguments: [errSecUserCanceled, errSecAuthFailed])
    func userCancelOrDenyIsADenial(status: OSStatus) {
        #expect(SecurityKeychainReader.error(for: status) == .denied)
    }

    @Test(arguments: [errSecInteractionNotAllowed, errSecNotAvailable, errSecParam])
    func lockedOrUnavailableKeychainIsTransientNotADenial(status: OSStatus) {
        #expect(SecurityKeychainReader.error(for: status) == .unavailable(status: status))
    }
}
