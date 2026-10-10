// FileSystem wrapper that forwards reads, counts bytes read per path and records every attempted write.
import ChoscorUsageCore
import Foundation
import Synchronization

/// Wraps another file system and counts writes so tests can prove read-only behavior, and bytes
/// read so tests can prove bounded reads.
public final class RecordingFileSystem: FileSystem {
    private let base: any FileSystem
    private let writes = Mutex<[String]>([])
    private let reads = Mutex<[String: Int]>([:])

    /// Wraps `base`.
    public init(_ base: any FileSystem) {
        self.base = base
    }

    /// Paths passed to `write(_:toPath:)`.
    public var writtenPaths: [String] { writes.withLock { $0 } }

    /// Bytes returned by whole-file and ranged reads of `path` so far.
    public func bytesRead(atPath path: String) -> Int { reads.withLock { $0[path, default: 0] } }

    /// The wrapped home directory.
    public var homeDirectory: String { base.homeDirectory }

    /// Forwards to the wrapped file system and counts the bytes returned.
    public func contents(atPath path: String) -> Data? {
        record(base.contents(atPath: path), path)
    }

    /// Forwards to the wrapped file system and counts the bytes returned.
    public func contents(atPath path: String, offset: Int, length: Int) -> Data? {
        record(base.contents(atPath: path, offset: offset, length: length), path)
    }

    /// Forwards to the wrapped file system.
    public func fileSize(atPath path: String) -> Int? { base.fileSize(atPath: path) }

    private func record(_ data: Data?, _ path: String) -> Data? {
        reads.withLock { $0[path, default: 0] += data?.count ?? 0 }
        return data
    }

    /// Forwards to the wrapped file system.
    public func directoryEntries(atPath path: String) -> [String] { base.directoryEntries(atPath: path) }

    /// Forwards to the wrapped file system.
    public func isDirectory(atPath path: String) -> Bool { base.isDirectory(atPath: path) }

    /// Forwards to the wrapped file system.
    public func fileExists(atPath path: String) -> Bool { base.fileExists(atPath: path) }

    /// Forwards to the wrapped file system.
    public func modificationDate(atPath path: String) -> Date? { base.modificationDate(atPath: path) }

    /// Records the path, then forwards the write.
    public func write(_ data: Data, toPath path: String) throws {
        writes.withLock { $0.append(path) }
        try base.write(data, toPath: path)
    }
}
