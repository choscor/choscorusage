// A real file system whose next write to one file blocks until the test releases it.
import ChoscorUsageCore
import ChoscorUsageProviders
import Foundation
import Synchronization

/// Holds the persistence actor inside a write so later saves queue up behind it.
final class BlockingFileSystem: FileSystem {
    private struct State {
        var blockedFileName: String?
        var isBlocked = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let base: LocalFileSystem
    private let state = Mutex(State())
    private let release = DispatchSemaphore(value: 0)

    init(homeDirectory: String) {
        base = LocalFileSystem(homeDirectory: homeDirectory)
    }

    var homeDirectory: String { base.homeDirectory }

    /// Makes the next write to a file named `fileName` block until ``unblock()``.
    func block(fileName: String) {
        state.withLock { $0.blockedFileName = fileName }
    }

    /// Returns once a write is blocked.
    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                guard !state.isBlocked else {
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if ready {
                continuation.resume()
            }
        }
    }

    /// Lets the blocked write finish.
    func unblock() {
        release.signal()
    }

    func write(_ data: Data, toPath path: String) throws {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>]? in
            guard let name = state.blockedFileName, path.hasSuffix("/\(name)") else {
                return nil
            }
            state.blockedFileName = nil
            state.isBlocked = true
            defer { state.waiters = [] }
            return state.waiters
        }
        if let waiters {
            waiters.forEach { $0.resume() }
            release.wait()
        }
        try base.write(data, toPath: path)
    }

    func contents(atPath path: String) -> Data? { base.contents(atPath: path) }

    func contents(atPath path: String, offset: Int, length: Int) -> Data? {
        base.contents(atPath: path, offset: offset, length: length)
    }

    func fileSize(atPath path: String) -> Int? { base.fileSize(atPath: path) }

    func directoryEntries(atPath path: String) -> [String] { base.directoryEntries(atPath: path) }

    func isDirectory(atPath path: String) -> Bool { base.isDirectory(atPath: path) }

    func fileExists(atPath path: String) -> Bool { base.fileExists(atPath: path) }

    func modificationDate(atPath path: String) -> Date? { base.modificationDate(atPath: path) }
}
