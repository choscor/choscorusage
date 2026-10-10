// Keeps each profile's Claude token in memory between fetches, so Keychain items are read rarely.
import ChoscorUsageCore
import Foundation
import Synchronization

/// In-memory token cache. Never written to disk or `UserDefaults`.
///
/// Each read of a Keychain item can prompt, so a token is kept until it expires, the endpoint
/// rejects it, the profile's directory or Keychain override changes, or the entry is discarded
/// (Retry or removal). The lock is held only for dictionary access, never across a read.
internal final class ClaudeCredentialCache: Sendable {
    private struct Entry {
        let configDirectory: String
        let keychainServiceOverride: String?
        let credentials: ClaudeCredentials
    }

    private let entries = Mutex<[UUID: Entry]>([:])

    /// Returns the cached credentials for `profile` when they were read for the same directory
    /// and override and have not expired by `now`; otherwise drops the entry and returns `nil`.
    internal func credentials(for profile: Profile, now: Date) -> ClaudeCredentials? {
        entries.withLock { entries in
            guard let entry = entries[profile.id] else {
                return nil
            }
            let isCurrent =
                entry.configDirectory == profile.configDirectory
                && entry.keychainServiceOverride == profile.keychainServiceOverride
                && (entry.credentials.expiresAt.map { $0 > now } ?? true)
            guard isCurrent else {
                entries[profile.id] = nil
                return nil
            }
            return entry.credentials
        }
    }

    /// Remembers `credentials` as read for `profile`'s current directory and override.
    internal func store(_ credentials: ClaudeCredentials, for profile: Profile) {
        let entry = Entry(
            configDirectory: profile.configDirectory, keychainServiceOverride: profile.keychainServiceOverride,
            credentials: credentials)
        entries.withLock { $0[profile.id] = entry }
    }

    /// Drops the entry for `profileID`, if any.
    internal func discard(_ profileID: UUID) {
        _ = entries.withLock { $0.removeValue(forKey: profileID) }
    }
}
