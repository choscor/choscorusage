// Profile management actions on UsageStore: discovery, add, rename, hide, reorder, remove.
import ChoscorUsageCore
import ChoscorUsageProviders
import Foundation

extension UsageStore {
    /// Runs discovery off the main actor and offers directories not already tracked.
    public func rescan() async {
        let dependencies = self.dependencies
        let existing = profiles
        candidates = await Task.detached {
            ProfileDiscovery(fileSystem: dependencies.fileSystem).discover(
                home: dependencies.fileSystem.homeDirectory, environment: dependencies.environment,
                keychain: dependencies.keychain, existing: existing)
        }.value
    }

    /// Adds confirmed candidates and removes them from the pending list.
    public func add(_ confirmed: [DiscoveredProfile]) {
        let before = Set(profiles.map(\.id))
        editProfiles { list in
            for candidate in confirmed {
                list.append(
                    provider: candidate.provider, directory: candidate.configDirectory,
                    displayName: candidate.displayName)
            }
        }
        candidates.removeAll { confirmed.contains($0) }
        fetchSoon(Set(profiles.map(\.id)).subtracting(before))
    }

    /// Drops all pending candidates without adding them.
    public func dismissCandidates() {
        candidates = []
    }

    /// Adds a directory the user picked, named after the directory.
    public func addProfile(provider: Provider, directory: String) {
        let name = ProfileDiscovery.defaultDisplayName(
            provider: provider,
            directoryName: ConfigPath.lastComponent(of: directory, home: dependencies.fileSystem.homeDirectory))
        let before = Set(profiles.map(\.id))
        editProfiles { $0.append(provider: provider, directory: directory, displayName: name) }
        fetchSoon(Set(profiles.map(\.id)).subtracting(before))
    }

    /// Renames a profile; blank names are ignored.
    public func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        editProfiles { $0.update(id) { $0.displayName = trimmed } }
    }

    /// Hides or shows a profile in the popover and summary; a shown profile is fetched now.
    public func setHidden(_ id: UUID, _ hidden: Bool) {
        editProfiles { $0.update(id) { $0.isHidden = hidden } }
        if !hidden {
            fetchSoon([id])
        }
    }

    /// Saves the Keychain service the user picked for a Claude profile, then retries it.
    public func setKeychainOverride(_ id: UUID, service: String?) async {
        editProfiles { $0.update(id) { $0.keychainServiceOverride = service } }
        await retry(id)
    }

    /// Lists `Claude Code-credentials*` Keychain services by attributes only, for the picker.
    public func keychainServiceNames() async -> [String] {
        let keychain = dependencies.keychain
        return await Task.detached {
            (try? keychain.serviceNames(withPrefix: ClaudeKeychainService.defaultName)) ?? []
        }.value
    }

    /// Reorders profiles, matching SwiftUI's `onMove`.
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        editProfiles { $0.move(fromOffsets: offsets, toOffset: destination) }
    }

    /// Removes a profile and its saved data.
    public func remove(_ id: UUID) {
        editProfiles { $0.remove(id) }
        discardData(for: id)
    }

    internal func editProfiles(_ change: (inout ProfileList) -> Void) {
        var list = ProfileList(profiles)
        change(&list)
        profiles = list.profiles
        saveProfiles()
    }

    internal func saveProfiles() {
        let snapshot = profiles
        let persistence = persistence
        let previous = pendingWrite
        pendingWrite = Task {
            await previous?.value
            try? await persistence.save(profiles: snapshot)
        }
    }
}
