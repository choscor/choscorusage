// The per-provider fetch seam the refresher drives.
import Foundation

/// Fetches one profile's usage. Implementations never refresh or write credentials.
public protocol UsageProviding: Sendable {
    /// Performs one attempt for `profile`. `allowingPrompt` is true only for a user action
    /// (Refresh Now or Retry); only then may a provider fall back to a credential read that can
    /// show a system prompt. Runs off the main actor; may block on a Keychain prompt.
    func fetch(_ profile: Profile, allowingPrompt: Bool) async -> UsageFetchOutcome

    /// Drops any credentials cached in memory for `profileID`, so its next fetch reads them
    /// again. Called on Retry and when a profile is removed. Any thread.
    func discardCachedCredentials(for profileID: UUID)
}

extension UsageProviding {
    /// Providers that cache nothing have nothing to drop.
    public func discardCachedCredentials(for _: UUID) {}
}
