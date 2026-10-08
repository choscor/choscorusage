// A config directory found by discovery, awaiting the user's confirmation.

/// A discovery candidate. Nothing is added until the user confirms it.
public struct DiscoveredProfile: Equatable, Sendable {
    /// The CLI the directory belongs to.
    public let provider: Provider
    /// The path exactly as found (home-relative scan) or as set in the environment.
    public let configDirectory: String
    /// The default display name derived from the directory name.
    public let displayName: String

    /// Creates a candidate.
    public init(provider: Provider, configDirectory: String, displayName: String) {
        self.provider = provider
        self.configDirectory = configDirectory
        self.displayName = displayName
    }
}
