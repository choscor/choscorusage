// The per-provider fetch seam the refresher drives.

/// Fetches one profile's usage. Implementations never refresh or write credentials.
public protocol UsageProviding: Sendable {
    /// Performs one attempt for `profile`. Runs off the main actor; may block on a Keychain prompt.
    func fetch(_ profile: Profile) async -> UsageFetchOutcome
}
