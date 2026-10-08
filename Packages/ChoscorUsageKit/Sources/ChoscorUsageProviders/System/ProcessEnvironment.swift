// EnvironmentReading backed by the app's own process environment.
import ChoscorUsageCore
import Foundation

/// Reads the app process's environment variables.
public struct ProcessEnvironment: EnvironmentReading {
    /// Creates a reader.
    public init() {}

    /// Returns the value, treating an empty string as unset.
    public func value(forKey key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }
}
