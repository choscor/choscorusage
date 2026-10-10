// Scripted CommandRunning fake that records every command it is asked to run.
import ChoscorUsageCore
import Foundation
import Synchronization

/// Answers `security find-generic-password` style commands by the value after `-s`.
public final class FakeCommandRunner: CommandRunning {
    /// One recorded call.
    public struct Call: Equatable, Sendable {
        /// The executable path.
        public let executable: String
        /// The arguments, in order.
        public let arguments: [String]
        /// The timeout passed in.
        public let timeout: Duration

        /// Creates a call record.
        public init(executable: String, arguments: [String], timeout: Duration) {
            self.executable = executable
            self.arguments = arguments
            self.timeout = timeout
        }
    }

    private let state = Mutex<(replies: [String: Result<CommandResult, CommandError>], calls: [Call])>(([:], []))

    /// Creates a runner whose unscripted services exit with 44 (item not found).
    public init() {}

    /// Calls received so far, in order.
    public var calls: [Call] { state.withLock { $0.calls } }

    /// Scripts the reply for commands naming `service`.
    public func reply(_ result: Result<CommandResult, CommandError>, forService service: String) {
        state.withLock { $0.replies[service] = result }
    }

    /// Scripts a successful read that prints `output` and a newline, as `security -w` does.
    public func output(_ output: String, forService service: String) {
        reply(.success(CommandResult(exitStatus: 0, standardOutput: Data("\(output)\n".utf8))), forService: service)
    }

    /// Scripts an exit with `status` and no output.
    public func exit(_ status: Int32, forService service: String) {
        reply(.success(CommandResult(exitStatus: status, standardOutput: Data())), forService: service)
    }

    /// Records the call and returns the scripted reply for the `-s` argument.
    public func run(
        _ executable: String, arguments: [String], timeout: Duration
    ) throws(CommandError)
        -> CommandResult
    {
        let service = arguments.firstIndex(of: "-s").map { arguments.index(after: $0) }
            .flatMap { arguments.indices.contains($0) ? arguments[$0] : nil }
        let reply = state.withLock { state in
            state.calls.append(Call(executable: executable, arguments: arguments, timeout: timeout))
            return service.flatMap { state.replies[$0] }
        }
        return try (reply ?? .success(CommandResult(exitStatus: 44, standardOutput: Data()))).get()
    }
}
