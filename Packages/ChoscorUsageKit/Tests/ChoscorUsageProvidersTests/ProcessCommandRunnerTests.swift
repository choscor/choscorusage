// Tests the Process-backed command runner against harmless system tools.
import ChoscorUsageCore
import Foundation
import Testing

@testable import ChoscorUsageProviders

struct ProcessCommandRunnerTests {
    private let runner = ProcessCommandRunner()

    @Test func collectsStandardOutputAndTheExitStatus() throws {
        let result = try runner.run("/bin/echo", arguments: ["a b", "$HOME"], timeout: .seconds(10))
        #expect(result == CommandResult(exitStatus: 0, standardOutput: Data("a b $HOME\n".utf8)))
        #expect(try runner.run("/usr/bin/false", arguments: [], timeout: .seconds(10)).exitStatus == 1)
    }

    @Test func outputLargerThanAPipeBufferIsReadInFull() throws {
        let result = try runner.run("/usr/bin/head", arguments: ["-c", "200000", "/dev/zero"], timeout: .seconds(10))
        #expect(result.standardOutput.count == 200_000)
    }

    @Test func aCommandThatOutlivesItsTimeoutIsTerminated() {
        let start = ContinuousClock.now
        #expect(throws: CommandError.timedOut) {
            try runner.run("/bin/sleep", arguments: ["30"], timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func aMissingExecutableFailsToLaunch() {
        #expect(throws: CommandError.launchFailed) {
            try runner.run("/nonexistent/tool", arguments: [], timeout: .seconds(1))
        }
    }

    @Test func aDescendantHoldingTheOutputOpenCannotBlockPastTheGracePeriod() {
        let start = ContinuousClock.now
        #expect(throws: CommandError.timedOut) {
            try runner.run("/bin/sh", arguments: ["-c", "/bin/sleep 30 &"], timeout: .seconds(10))
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}
