// CommandRunning backed by Foundation's Process, with a timeout and no shell.
import ChoscorUsageCore
import Foundation
import Synchronization

/// Runs commands as child processes. Standard input and error are the null device, so nothing
/// the tool prints about a failure is captured or logged.
public struct ProcessCommandRunner: CommandRunning {
    /// How long a terminated process gets to exit before it is killed, and how long output may
    /// keep arriving after the process exits (a descendant could hold the pipe open).
    private static let grace = DispatchTimeInterval.seconds(2)

    /// Creates a runner.
    public init() {}

    /// Launches `executable` directly (no shell) and waits for it to exit. Output is read while
    /// the process runs, so output larger than a pipe buffer cannot stall it. After `timeout`
    /// the process is terminated (killed if it ignores that) and ``CommandError/timedOut`` is
    /// thrown, as it is when a descendant keeps the output open past a short grace period.
    /// Blocks the calling thread; call it off the main actor.
    public func run(_ executable: String, arguments: [String], timeout: Duration) throws(CommandError) -> CommandResult
    {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw .launchFailed
        }
        let reader = OutputReader(output.fileHandleForReading)
        guard exited.wait(timeout: .now() + Self.interval(timeout)) == .success else {
            Self.stop(process, exited: exited)
            _ = reader.wait(for: Self.grace)
            throw .timedOut
        }
        guard let data = reader.wait(for: Self.grace) else {
            throw .timedOut
        }
        return CommandResult(exitStatus: process.terminationStatus, standardOutput: data)
    }

    /// Terminates, then kills a process that ignores it. `isRunning` guards the kill so a PID
    /// reused after the child was reaped is never signalled.
    private static func stop(_ process: Process, exited: DispatchSemaphore) {
        process.terminate()
        if exited.wait(timeout: .now() + grace) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
    }

    private static func interval(_ duration: Duration) -> DispatchTimeInterval {
        let parts = duration.components
        let nanoseconds = parts.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !nanoseconds.overflow else {
            return .never
        }
        return .nanoseconds(Int(nanoseconds.partialValue + parts.attoseconds / 1_000_000_000))
    }
}

/// Drains a pipe on a background queue until every writer closes it.
private final class OutputReader: Sendable {
    private let data = Mutex(Data())
    private let finished = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let bytes = (try? handle.readToEnd()) ?? Data()
            data.withLock { $0 = bytes }
            finished.signal()
        }
    }

    /// Returns everything read once the pipe reaches end of file, or `nil` after `limit`. The
    /// handle is not closed on timeout: closing a descriptor another thread is reading could
    /// make that read hit a reused descriptor. The read ends when the last writer exits.
    func wait(for limit: DispatchTimeInterval) -> Data? {
        guard finished.wait(timeout: .now() + limit) == .success else {
            return nil
        }
        return data.withLock { $0 }
    }
}
