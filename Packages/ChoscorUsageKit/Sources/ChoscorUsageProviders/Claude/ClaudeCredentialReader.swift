// Reads Claude Code OAuth credentials from the Keychain or the config directory, read-only.
import ChoscorUsageCore
import Foundation

/// Looks up a profile's Claude OAuth token. Never refreshes, writes or deletes anything.
///
/// Each call reads each candidate Keychain item at most once per reader, and the direct
/// reader only after the first reader failed; a denial stops immediately so one refresh cycle
/// produces at most one prompt per profile.
public struct ClaudeCredentialReader: Sendable {
    private struct Record: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double?
        }

        let claudeAiOauth: OAuth?
    }

    private enum ItemRead: Equatable {
        case found(ClaudeCredentials)
        case missing
        case denied
        case unavailable
    }

    private let keychain: any KeychainReading
    private let directKeychain: any KeychainReading
    private let fileSystem: any FileSystem

    /// Creates a reader. `keychain` is tried first (the security CLI in the app);
    /// `directKeychain` reads the item in-process and is used only when the first read fails
    /// and the caller allows it.
    public init(keychain: any KeychainReading, directKeychain: any KeychainReading, fileSystem: any FileSystem) {
        self.keychain = keychain
        self.directKeychain = directKeychain
        self.fileSystem = fileSystem
    }

    /// Returns the profile's credentials: the user's Keychain override if set, else the computed
    /// Keychain services, else `<config-dir>/.credentials.json`. Each item is read through the
    /// first reader; only when that read fails (an error, or output that is not Claude
    /// credentials) and `allowingDirectRead` is true is it read again directly, which may prompt.
    /// A missing item is never retried. A denial from either reader stops at once. A Keychain
    /// that cannot be read is reported only when the file has no token either. Blocks; call it
    /// off the main actor.
    public func read(for profile: Profile, allowingDirectRead: Bool) -> ClaudeCredentialResult {
        let services =
            profile.keychainServiceOverride.map { [$0] }
            ?? ClaudeKeychainService.candidates(
                forConfigDir: profile.configDirectory, home: fileSystem.homeDirectory)
        var keychainUnavailable = false
        for service in services {
            switch readItem(service, allowingDirectRead: allowingDirectRead) {
            case .found(let credentials):
                return .found(credentials)
            case .denied:
                return .keychainDenied
            case .unavailable:
                keychainUnavailable = true
            case .missing:
                continue
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

    private func readItem(_ service: String, allowingDirectRead: Bool) -> ItemRead {
        let first = Self.read(service, from: keychain)
        guard first == .unavailable, allowingDirectRead else {
            return first
        }
        return Self.read(service, from: directKeychain)
    }

    private static func read(_ service: String, from reader: any KeychainReading) -> ItemRead {
        do {
            guard let data = try reader.genericPassword(service: service) else {
                return .missing
            }
            return decode(data).map(ItemRead.found) ?? .unavailable
        } catch .denied {
            return .denied
        } catch {
            return .unavailable
        }
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
