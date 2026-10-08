// The injectable file-system seam rooted at the user's home directory.
import Foundation

/// File access used by credential readers, discovery, log parsing and persistence.
public protocol FileSystem: Sendable {
    /// Absolute path of the current user's home directory.
    var homeDirectory: String { get }

    /// Returns the file's bytes, or `nil` when it is missing or unreadable.
    func contents(atPath path: String) -> Data?

    /// Returns the names of the entries in a directory, or an empty array.
    func directoryEntries(atPath path: String) -> [String]

    /// Returns whether `path` exists and is a directory.
    func isDirectory(atPath path: String) -> Bool

    /// Returns whether a file or directory exists at `path`.
    func fileExists(atPath path: String) -> Bool

    /// Returns the modification date of `path`, if it exists.
    func modificationDate(atPath path: String) -> Date?

    /// Atomically writes `data`, creating parent directories. Only the app's own Application
    /// Support directory is ever written; CLI config directories are read-only to the app.
    func write(_ data: Data, toPath path: String) throws
}
