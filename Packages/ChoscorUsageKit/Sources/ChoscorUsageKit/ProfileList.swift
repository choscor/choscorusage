// Ordered profile editing: add, rename, hide, reorder and remove with contiguous order indexes.
import ChoscorUsageCore
import Foundation

/// The user's profiles in display order. Every mutation renumbers `order` from 0.
internal struct ProfileList: Equatable {
    internal private(set) var profiles: [Profile]

    internal init(_ profiles: [Profile]) {
        self.profiles = profiles.sorted { $0.order < $1.order }
        renumber()
    }

    internal mutating func append(provider: Provider, directory: String, displayName: String) {
        profiles.append(
            Profile(provider: provider, configDirectory: directory, displayName: displayName, order: profiles.count))
    }

    internal mutating func update(_ id: UUID, _ change: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        change(&profiles[index])
    }

    internal mutating func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        renumber()
    }

    /// Moves the profiles at `offsets` to before `destination`, matching SwiftUI's `onMove`.
    internal mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.map { profiles[$0] }
        var remaining = profiles.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.count { $0 < destination }
        remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
        profiles = remaining
        renumber()
    }

    private mutating func renumber() {
        for index in profiles.indices {
            profiles[index].order = index
        }
    }
}
