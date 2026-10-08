// Persistable dedupe state for notifications, so a relaunch never repeats one.
import Foundation

/// Remembers which alerts were delivered and which windows reached 80%.
public struct NotificationLedger: Codable, Equatable, Sendable {
    /// What a dedupe key refers to.
    public enum Kind: String, Codable, Sendable {
        /// The window first reached 80%.
        case percent80
        /// The window first reached 95%.
        case percent95
        /// A window that had reached 80% reset.
        case reset
    }

    /// Dedupe key `(profileID, windowID, resetsAt, threshold)`.
    public struct Key: Codable, Hashable, Sendable {
        /// The profile the window belongs to.
        public let profileID: UUID
        /// The window's identifier within the profile.
        public let windowID: String
        /// The window's reset time, rounded to the minute to absorb provider jitter.
        public let resetsAt: Date?
        /// Which alert this key records.
        public let kind: Kind
    }

    /// Delivered (or deliberately skipped) alerts.
    public private(set) var delivered: Set<Key> = []
    /// Windows that reached 80%, keyed by `profileID|windowID`, with their reset time then.
    public private(set) var armed: [String: Date] = [:]
    /// Armed windows whose provider reported no reset time.
    public private(set) var armedWithoutReset: Set<String> = []

    /// Creates an empty ledger.
    public init() {}

    internal mutating func record(_ key: Key) -> Bool {
        delivered.insert(key).inserted
    }

    internal mutating func arm(_ windowKey: String, resetsAt: Date?) {
        if let resetsAt {
            armed[windowKey] = resetsAt
        } else {
            armedWithoutReset.insert(windowKey)
        }
    }

    /// Ends a window's cycle. Keys without a reset time cannot tell cycles apart, so they are
    /// dropped here to let the next cycle alert again.
    internal mutating func disarm(_ windowKey: String, profileID: UUID, windowID: String) {
        armed[windowKey] = nil
        armedWithoutReset.remove(windowKey)
        delivered = delivered.filter { $0.resetsAt != nil || $0.profileID != profileID || $0.windowID != windowID }
    }

    /// Drops everything recorded for a removed profile.
    public mutating func forget(profileID: UUID) {
        let prefix = "\(profileID.uuidString)|"
        delivered = delivered.filter { $0.profileID != profileID }
        armed = armed.filter { !$0.key.hasPrefix(prefix) }
        armedWithoutReset = armedWithoutReset.filter { !$0.hasPrefix(prefix) }
    }

    internal func isArmed(_ windowKey: String) -> Bool {
        armed[windowKey] != nil || armedWithoutReset.contains(windowKey)
    }

    /// Drops keys for windows that reset more than a day before `now`, bounding the file.
    internal mutating func prune(before now: Date) {
        let cutoff = now.addingTimeInterval(-86_400)
        delivered = delivered.filter { key in key.resetsAt.map { $0 >= cutoff } ?? true }
    }
}
