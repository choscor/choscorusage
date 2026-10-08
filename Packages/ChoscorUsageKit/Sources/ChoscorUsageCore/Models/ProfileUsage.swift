// Pairs a profile with its refresh state and last good snapshot for presentation.
import Foundation

/// A profile, the state of its latest refresh, and its last good data.
public struct ProfileUsage: Equatable, Sendable, Identifiable {
    /// The profile being described.
    public let profile: Profile
    /// Outcome of the latest refresh.
    public let state: ProfileState
    /// The most recent successful reading, if any.
    public let snapshot: UsageSnapshot?

    /// The profile's identifier.
    public var id: UUID { profile.id }

    /// Creates a pairing.
    public init(profile: Profile, state: ProfileState, snapshot: UsageSnapshot?) {
        self.profile = profile
        self.state = state
        self.snapshot = snapshot
    }
}
