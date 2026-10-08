// Dictionary-backed EnvironmentReading fake.
import ChoscorUsageCore

/// Environment variables supplied by a test.
public struct FakeEnvironment: EnvironmentReading {
    private let values: [String: String]

    /// Creates an environment holding `values`.
    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    /// Returns the value for `key`, treating empty strings as unset.
    public func value(forKey key: String) -> String? {
        values[key].flatMap { $0.isEmpty ? nil : $0 }
    }
}
