// Security-framework KeychainReading that only ever queries generic-password items.
import ChoscorUsageCore
import Foundation
import Security
import Synchronization

/// Reads generic-password items. Uses `SecItemCopyMatching` only; there is no add, update or
/// delete call anywhere in the app.
public struct SecurityKeychainReader: KeychainReading {
    /// Serializes item reads so concurrent refreshes never stack several access prompts.
    private static let readLock = Mutex(())

    /// Creates a reader.
    public init() {}

    /// Returns the item data for `service`. May present the system access prompt; Cancel or Deny
    /// surfaces as ``KeychainError/denied``; reads
    /// run one at a time.
    public func genericPassword(service: String) throws(KeychainError) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        let (status, data) = Self.readLock.withLock { _ -> (OSStatus, Data?) in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        }
        switch status {
        case errSecSuccess:
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw Self.error(for: status)
        }
    }

    /// Maps a failed read. Only Cancel or Deny is a denial; `errSecInteractionNotAllowed` (a locked
    /// keychain, e.g. before first unlock) is transient and retried on the next refresh.
    internal static func error(for status: OSStatus) -> KeychainError {
        switch status {
        case errSecUserCanceled, errSecAuthFailed:
            return .denied
        default:
            return .unavailable(status: status)
        }
    }

    /// Lists service names by attributes only (no `kSecReturnData`), which never prompts.
    public func serviceNames(withPrefix prefix: String) throws(KeychainError) -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw .unavailable(status: status)
        }
        let services = items.compactMap { $0[kSecAttrService as String] as? String }.filter { $0.hasPrefix(prefix) }
        return Array(Set(services)).sorted()
    }
}
