// Reads and writes one Codable value as a JSON file in Application Support.
import ChoscorUsageCore
import Foundation

/// A JSON file holding one value. Writes are atomic; unreadable files load as `nil`.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    /// Absolute path of the file.
    public let path: String
    private let fileSystem: any FileSystem

    /// Creates a store for `fileName` inside `directory`.
    public init(fileSystem: any FileSystem, directory: String, fileName: String) {
        self.fileSystem = fileSystem
        path = "\(directory)/\(fileName)"
    }

    /// Returns the decoded value, or `nil` when the file is missing or no longer decodes.
    public func load() -> Value? {
        guard let data = fileSystem.contents(atPath: path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    /// Atomically replaces the file with `value`.
    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileSystem.write(try encoder.encode(value), toPath: path)
    }
}
