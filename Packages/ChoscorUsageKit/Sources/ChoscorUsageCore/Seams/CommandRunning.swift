// The injectable seam for running a command-line tool and collecting its output.
import Foundation

/// What a finished command produced.
public struct CommandResult: Equatable, Sendable {
    /// The process's exit status.
    public let exitStatus: Int32
    /// Everything written to standard output. May hold secrets; never log or persist it.
    public let standardOutput: Data

    /// Creates a result.
    public init(exitStatus: Int32, standardOutput: Data) {
        self.exitStatus = exitStatus
        self.standardOutput = standardOutput
    }
}

/// Why a command produced no result.
public enum CommandError: Error, Equatable, Sendable {
    /// The executable could not be started.
    case launchFailed
    /// The command ran past its timeout and was terminated.
    case timedOut
}

/// Runs an executable by absolute path with an argument array, never through a shell, so no
/// argument is ever interpreted. Standard error is discarded.
public protocol CommandRunning: Sendable {
    /// Runs `executable` with `arguments` and waits for it to exit, terminating it after
    /// `timeout`. Blocks the calling thread; call it off the main actor.
    func run(_ executable: String, arguments: [String], timeout: Duration) throws(CommandError) -> CommandResult
}
