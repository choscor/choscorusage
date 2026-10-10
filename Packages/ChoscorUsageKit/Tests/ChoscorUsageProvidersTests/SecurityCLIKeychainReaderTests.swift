// Tests reading Keychain items through the security CLI: arguments, output and exit statuses.
import ChoscorUsageCore
import ChoscorUsageTestSupport
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct SecurityCLIKeychainReaderTests {
    private let runner = FakeCommandRunner()
    private let attributes = FakeKeychain(items: ["Claude Code-credentials-1": .success(Data())])
    private var reader: SecurityCLIKeychainReader { SecurityCLIKeychainReader(runner: runner, attributes: attributes) }

    @Test func runsTheAbsoluteSecurityPathWithAnArgumentArrayAndABoundedTimeout() throws {
        runner.output("{}", forService: "svc")
        _ = try reader.genericPassword(service: "svc", account: "acct")
        _ = try reader.genericPassword(service: "svc", account: nil)
        #expect(
            runner.calls == [
                .init(
                    executable: "/usr/bin/security",
                    arguments: ["find-generic-password", "-s", "svc", "-a", "acct", "-w"],
                    timeout: .seconds(60)),
                .init(
                    executable: "/usr/bin/security", arguments: ["find-generic-password", "-s", "svc", "-w"],
                    timeout: .seconds(60)),
            ])
    }

    @Test func returnsTheOutputWithoutItsTrailingNewline() throws {
        runner.output(#"{"claudeAiOauth":{"accessToken":"t"}}"#, forService: "svc")
        #expect(
            try reader.genericPassword(service: "svc", account: nil)
                == Data(#"{"claudeAiOauth":{"accessToken":"t"}}"#.utf8))
    }

    @Test func aMissingItemIsNil() throws {
        runner.exit(44, forService: "svc")
        #expect(try reader.genericPassword(service: "svc", account: nil) == nil)
    }

    @Test(arguments: [Int32(128), 51])
    func cancelOrDenyIsADenial(status: Int32) {
        runner.exit(status, forService: "svc")
        #expect(throws: KeychainError.denied) { try reader.genericPassword(service: "svc", account: nil) }
    }

    @Test(arguments: [
        Result<CommandResult, CommandError>.success(CommandResult(exitStatus: 36, standardOutput: Data())),
        .success(CommandResult(exitStatus: 1, standardOutput: Data())),
        .failure(.timedOut), .failure(.launchFailed),
    ])
    func anythingElseIsUnavailable(reply: Result<CommandResult, CommandError>) {
        runner.reply(reply, forService: "svc")
        #expect {
            try reader.genericPassword(service: "svc", account: nil)
        } throws: { error in
            guard case .unavailable = error as? KeychainError else {
                return false
            }
            return true
        }
    }

    @Test func listingUsesTheAttributeOnlyReaderAndRunsNoCommand() throws {
        #expect(try reader.serviceNames(withPrefix: "Claude Code-credentials") == ["Claude Code-credentials-1"])
        #expect(attributes.listings == 1)
        #expect(runner.calls.isEmpty)
    }

    /// Needs a login keychain; a CI runner without one may exit with another status.
    @Test(
        .enabled(if: FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/Library/Keychains/login.keychain-db"))
    )
    func theRealSecurityToolReportsAMissingItemAsNil() throws {
        let reader = SecurityCLIKeychainReader(runner: ProcessCommandRunner(), attributes: attributes)
        #expect(
            try reader.genericPassword(service: "ChoscorUsage-test-missing-\(UUID().uuidString)", account: nil) == nil)
    }
}
