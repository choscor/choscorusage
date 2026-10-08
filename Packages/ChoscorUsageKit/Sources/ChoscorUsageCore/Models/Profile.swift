// A user-visible account: one CLI config directory and how it is presented.
import Foundation

/// One Claude Code or Codex config directory tracked by the app.
public struct Profile: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Stable identity that survives renames and reorders.
    public let id: UUID
    /// The CLI this directory belongs to.
    public var provider: Provider
    /// Absolute config-directory path, stored exactly as entered or discovered.
    public var configDirectory: String
    /// Name shown in the menu bar popover and notifications.
    public var displayName: String
    /// Position in the user's ordering; lower values come first.
    public var order: Int
    /// Hidden profiles are kept but neither refreshed for display nor summarized.
    public var isHidden: Bool
    /// A Keychain service picked by the user when the computed Claude service is missing.
    public var keychainServiceOverride: String?

    /// Creates a profile. `id` defaults to a new UUID.
    public init(
        id: UUID = UUID(),
        provider: Provider,
        configDirectory: String,
        displayName: String,
        order: Int,
        isHidden: Bool = false,
        keychainServiceOverride: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.configDirectory = configDirectory
        self.displayName = displayName
        self.order = order
        self.isHidden = isHidden
        self.keychainServiceOverride = keychainServiceOverride
    }
}
