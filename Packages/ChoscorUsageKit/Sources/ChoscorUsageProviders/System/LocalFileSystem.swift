// FileManager-backed FileSystem rooted at a home directory.
import ChoscorUsageCore
import Foundation

/// The real file system. Reads anywhere; writes only where callers direct it (the app's
/// Application Support directory).
public struct LocalFileSystem: FileSystem {
    /// The home directory used for discovery and `~` expansion.
    public let homeDirectory: String

    /// Creates a file system rooted at `homeDirectory`, defaulting to the user's home.
    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    /// Returns the file's bytes, or `nil` when missing or unreadable.
    public func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    /// Returns entry names in a directory, or an empty array.
    public func directoryEntries(atPath path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    /// Returns whether `path` is a directory.
    public func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Returns whether anything exists at `path`.
    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Returns the modification date of `path`.
    public func modificationDate(atPath path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Atomically writes `data`, creating parent directories.
    public func write(_ data: Data, toPath path: String) throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
