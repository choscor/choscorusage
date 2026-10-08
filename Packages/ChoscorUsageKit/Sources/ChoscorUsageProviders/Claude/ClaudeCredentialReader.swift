// Reads Claude Code OAuth credentials from the Keychain or the config directory, read-only.
import ChoscorUsageCore
import Foundation

/// Looks up a profile's Claude OAuth token. Never refreshes, writes or deletes anything.
///
/// Each call reads each candidate Keychain item at most once; a denial stops immediately so
/// one refresh cycle produces at most one prompt per profile.
public struct ClaudeCredentialReader: Sendable {
    private struct Record: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double?
        }

        let claudeAiOauth: OAuth?
    }

    private let keychain: any KeychainReading
    private let fileSystem: any FileSystem

    /// Creates a reader over the given seams.
    public init(keychain: any KeychainReading, fileSystem: any FileSystem) {
        self.keychain = keychain
        self.fileSystem = fileSystem
    }

    /// Returns the profile's credentials: the user's Keychain override if set, else the computed
    /// Keychain services, else `<config-dir>/.credentials.json`. A Keychain that cannot be read
    /// is reported only when the file has no token either. Blocks on Keychain prompts; call
    /// it off the main actor.
    public func read(for profile: Profile) -> ClaudeCredentialResult {
        let services =
            profile.keychainServiceOverride.map { [$0] }
            ?? ClaudeKeychainService.candidates(
                forConfigDir: profile.configDirectory, home: fileSystem.homeDirectory)
        var keychainUnavailable = false
        for service in services {
            do {
                if let data = try keychain.genericPassword(service: service), let credentials = Self.decode(data) {
                    return .found(credentials)
                }
            } catch .denied {
                return .keychainDenied
            } catch {
                keychainUnavailable = true
            }
        }
        let directory = ConfigPath.standardized(profile.configDirectory, home: fileSystem.homeDirectory)
        guard let data = fileSystem.contents(atPath: "\(directory)/.credentials.json"),
            let credentials = Self.decode(data)
        else {
            return keychainUnavailable ? .keychainUnavailable : .notFound
        }
        return .found(credentials)
    }

    private static func decode(_ data: Data) -> ClaudeCredentials? {
        guard let oauth = (try? JSONDecoder().decode(Record.self, from: data))?.claudeAiOauth else {
            return nil
        }
        // Claude Code records `expiresAt` in epoch milliseconds.
        let expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1_000 : $0) }
        return ClaudeCredentials(accessToken: oauth.accessToken, expiresAt: expiresAt)
    }
}
