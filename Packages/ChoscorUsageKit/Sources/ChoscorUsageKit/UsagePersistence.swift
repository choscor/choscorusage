// Application Support persistence for profiles, last good snapshots and notification dedupe.
import ChoscorUsageCore
import Foundation

/// Serializes all Application Support file I/O off the main actor.
public actor UsagePersistence {
    /// What a launch restores.
    public struct Restored: Sendable {
        /// Saved profiles, or `nil` on first launch.
        public let profiles: [Profile]?
        /// Last good snapshot per profile.
        public let snapshots: [UUID: UsageSnapshot]
        /// Notification dedupe state.
        public let ledger: NotificationLedger
    }

    /// `~/Library/Application Support/com.choscor.ChoscorUsage` for `home`.
    public static func directory(home: String) -> String {
        "\(home)/Library/Application Support/com.choscor.ChoscorUsage"
    }

    private let profiles: JSONFileStore<[Profile]>
    private let snapshots: JSONFileStore<[UUID: UsageSnapshot]>
    private let ledger: JSONFileStore<NotificationLedger>

    /// Creates persistence in the app's Application Support directory under `fileSystem`'s home.
    public init(fileSystem: any FileSystem) {
        let directory = Self.directory(home: fileSystem.homeDirectory)
        profiles = JSONFileStore(fileSystem: fileSystem, directory: directory, fileName: "profiles.json")
        snapshots = JSONFileStore(fileSystem: fileSystem, directory: directory, fileName: "snapshots.json")
        ledger = JSONFileStore(fileSystem: fileSystem, directory: directory, fileName: "notification-ledger.json")
    }

    /// Loads everything; missing or unreadable files restore as empty.
    public func restore() -> Restored {
        Restored(
            profiles: profiles.load(), snapshots: snapshots.load() ?? [:], ledger: ledger.load() ?? NotificationLedger()
        )
    }

    /// Saves the profile list.
    public func save(profiles value: [Profile]) throws {
        try profiles.save(value)
    }

    /// Saves last good snapshots and the notification ledger after a refresh.
    public func save(snapshots value: [UUID: UsageSnapshot], ledger ledgerValue: NotificationLedger) throws {
        try snapshots.save(value)
        try ledger.save(ledgerValue)
    }
}
