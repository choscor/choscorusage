// A throwaway home directory tree for tests that use the real file system.
import Foundation

/// A unique temporary directory, removed when the value is deinitialized.
public final class TemporaryHome: Sendable {
    /// Absolute path of the directory.
    public let path: String

    /// Creates an empty directory under the system temporary directory.
    public init() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "choscorusage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = url.path(percentEncoded: false).trimmingSuffix("/")
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Writes `contents` at `relative`, creating parents, and optionally sets its modification date.
    @discardableResult
    public func write(_ relative: String, _ contents: String, modified: Date? = nil) throws -> String {
        let full = "\(path)/\(relative)"
        let parent = (full as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(filePath: full))
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: full)
        }
        return full
    }

    /// Creates an empty directory at `relative`.
    public func makeDirectory(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: "\(path)/\(relative)", withIntermediateDirectories: true)
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
