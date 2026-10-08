// Loads synthetic JSON and JSONL fixtures bundled with the Providers tests.
import Foundation
import Testing

enum FixtureLoader {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        try #require(String(bytes: try data(name), encoding: .utf8))
    }
}
