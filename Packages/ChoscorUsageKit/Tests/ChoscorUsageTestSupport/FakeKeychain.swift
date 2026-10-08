// In-memory KeychainReading fake that records every call it receives.
import ChoscorUsageCore
import Foundation
import Synchronization

/// A scripted Keychain. Items map service names (`service#account` when an account is given) to
/// data or to an error.
public final class FakeKeychain: KeychainReading {
    private let state: Mutex<(items: [String: Result<Data, KeychainError>], reads: [String], listings: Int)>

    /// Creates a keychain holding `items`.
    public init(items: [String: Result<Data, KeychainError>] = [:]) {
        state = Mutex((items, [], 0))
    }

    /// Services (`service#account` with an account) whose data was requested, in order.
    public var reads: [String] { state.withLock { $0.reads } }

    /// Number of attribute-only listings.
    public var listings: Int { state.withLock { $0.listings } }

    /// Replaces the item for `service` and, if given, `account`.
    public func set(_ service: String, account: String? = nil, _ result: Result<Data, KeychainError>?) {
        state.withLock { $0.items[Self.key(service, account)] = result }
    }

    /// Records the read and returns the scripted item.
    public func genericPassword(service: String, account: String?) throws(KeychainError) -> Data? {
        let key = Self.key(service, account)
        let item = state.withLock { state in
            state.reads.append(key)
            return state.items[key]
        }
        return try item?.get()
    }

    private static func key(_ service: String, _ account: String?) -> String {
        account.map { "\(service)#\($0)" } ?? service
    }

    /// Lists scripted services with `prefix`.
    public func serviceNames(withPrefix prefix: String) throws(KeychainError) -> [String] {
        state.withLock { state in
            state.listings += 1
            return state.items.keys.filter { $0.hasPrefix(prefix) }.sorted()
        }
    }
}
