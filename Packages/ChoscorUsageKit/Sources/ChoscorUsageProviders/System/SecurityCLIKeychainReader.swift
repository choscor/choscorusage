// KeychainReading that reads item data through `/usr/bin/security`, which Claude Code's items trust.
import ChoscorUsageCore
import Foundation

/// Reads generic-password data by running `security find-generic-password -w`.
///
/// Claude Code creates and rewrites its `Claude Code-credentials*` items with `/usr/bin/security`,
/// so each item's access list trusts that tool and reading through it normally shows no prompt.
/// Reading with `SecItemCopyMatching` instead prompts again every time Claude Code renews its
/// token (about every 8 hours), because the rewrite drops the app's "Always Allow" grant. Sources:
/// https://www.silverfort.com/blog/skipping-the-lock-a-claude-code-cli-weakness-lets-any-macos-process-read-stored-credentials/
/// and https://github.com/steipete/CodexBar/blob/main/docs/claude.md (both verified 2026-10-10).
///
/// Output, errors and arguments are never logged: the output is the credential itself.
public struct SecurityCLIKeychainReader: KeychainReading {
    private static let executable = "/usr/bin/security"
    /// Long enough for a person to answer a prompt if a future item stops trusting the tool.
    private static let timeout = Duration.seconds(60)
    /// `security` exits with the low byte of the failing `OSStatus`: errSecItemNotFound (-25300)
    /// exits 44, observed on macOS 26 on 2026-10-10. Cancel (errSecUserCanceled, -128 → 128) and
    /// Deny (errSecAuthFailed, -25293 → 51) are derived from that rule and not yet observed at a
    /// real prompt; an unmapped status falls back to `.unavailable`.
    private static let itemNotFound: Int32 = 44
    private static let denials: Set<Int32> = [128, 51]
    /// Reported for a launch failure or timeout, which have no exit status.
    private static let noExitStatus: Int32 = -1

    private let runner: any CommandRunning
    private let attributes: any KeychainReading

    /// Creates a reader that runs commands through `runner` and lists services through
    /// `attributes`, whose listing never prompts.
    public init(runner: any CommandRunning, attributes: any KeychainReading) {
        self.runner = runner
        self.attributes = attributes
    }

    /// Returns the item's data without the newline `security` appends, or `nil` when no such item
    /// exists. Cancel or Deny in a prompt is ``KeychainError/denied``; any other failure, including
    /// a 60-second timeout, is ``KeychainError/unavailable(status:)`` carrying the exit status (or
    /// -1). Blocks; call it off the main actor.
    public func genericPassword(service: String, account: String?) throws(KeychainError) -> Data? {
        var arguments = ["find-generic-password", "-s", service]
        if let account {
            arguments += ["-a", account]
        }
        arguments.append("-w")
        let result: CommandResult
        do {
            result = try runner.run(Self.executable, arguments: arguments, timeout: Self.timeout)
        } catch {
            throw .unavailable(status: Self.noExitStatus)
        }
        switch result.exitStatus {
        case 0:
            return Self.trimmingTrailingNewline(result.standardOutput)
        case Self.itemNotFound:
            return nil
        case let status where Self.denials.contains(status):
            throw .denied
        case let status:
            throw .unavailable(status: status)
        }
    }

    /// Lists service names through the attribute-only reader.
    public func serviceNames(withPrefix prefix: String) throws(KeychainError) -> [String] {
        try attributes.serviceNames(withPrefix: prefix)
    }

    private static func trimmingTrailingNewline(_ output: Data) -> Data {
        output.last == UInt8(ascii: "\n") ? Data(output.dropLast()) : output
    }
}
