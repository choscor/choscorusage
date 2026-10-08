// FileSystem wrapper that forwards reads and records every attempted write.
import ChoscorUsageCore
import Foundation
import Synchronization

/// Wraps another file system and counts writes so tests can prove read-only behavior.
public final class RecordingFileSystem: FileSystem {
    private let base: any FileSystem
    private let writes = Mutex<[String]>([])

    /// Wraps `base`.
    public init(_ base: any FileSystem) {
        self.base = base
    }

    /// Paths passed to `write(_:toPath:)`.
    public var writtenPaths: [String] { writes.withLock { $0 } }

    /// The wrapped home directory.
    public var homeDirectory: String { base.homeDirectory }

    /// Forwards to the wrapped file system.
    public func contents(atPath path: String) -> Data? { base.contents(atPath: path) }

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
