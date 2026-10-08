// The injectable, read-only Keychain seam used for Claude Code and Codex credentials.
import Foundation

/// Why a Keychain read failed.
public enum KeychainError: Error, Equatable, Sendable {
    /// The user denied access or pressed Cancel in the Keychain prompt.
    case denied
    /// Any other Security framework status.
    case unavailable(status: Int32)
}

/// Reads generic-password items. There is deliberately no write API: the app never stores,
/// refreshes or deletes CLI credentials.
public protocol KeychainReading: Sendable {
    /// Returns the data of the item for `service` (and `account`, when given), or `nil` when no
    /// such item exists. May show a system prompt and block; call it off the main actor.
    func genericPassword(service: String, account: String?) throws(KeychainError) -> Data?

    /// Lists generic-password service names beginning with `prefix` by attributes only, without
    /// reading item data, so it never prompts.
    func serviceNames(withPrefix prefix: String) throws(KeychainError) -> [String]
}

extension KeychainReading {
    /// Returns the data of the first item for `service`, whatever its account.
    public func genericPassword(service: String) throws(KeychainError) -> Data? {
        try genericPassword(service: service, account: nil)
    }
}
