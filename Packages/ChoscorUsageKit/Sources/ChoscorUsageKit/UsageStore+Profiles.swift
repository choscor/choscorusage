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

    /// Adds confirmed candidates and removes them from the pending list. A candidate whose folder
    /// is already tracked (added by hand after the scan) is skipped, so no Keychain item is read
    /// twice per cycle.
    public func add(_ confirmed: [DiscoveredProfile]) {
        let before = Set(profiles.map(\.id))
        var tracked = Set(profiles.map { standardized($0.configDirectory) })
        editProfiles { list in
            for candidate in confirmed where tracked.insert(standardized(candidate.configDirectory)).inserted {
                list.append(
                    provider: candidate.provider, directory: candidate.configDirectory,
                    displayName: candidate.displayName)
            }
        }
        candidates.removeAll { confirmed.contains($0) }
        fetchSoon(Set(profiles.map(\.id)).subtracting(before))
    }

    /// Drops the given candidates without adding them; others stay pending.
    public func dismiss(_ dismissed: [DiscoveredProfile]) {
        candidates.removeAll { dismissed.contains($0) }
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

    /// Hides or shows a profile in the menu and summary; a shown profile is fetched now.
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

    /// Removes a profile and its saved data, and stops showing it in the menu bar.
    public func remove(_ id: UUID) {
        editProfiles { $0.remove(id) }
        if preferences.chosenProfileID == id {
            preferences.chosenProfileID = nil
        }
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

/// What happened when the user picked a folder to add as a profile.
public enum AddProfileOutcome: Equatable, Sendable {
    /// The folder was added as this profile.
    case added(Profile)
    /// The folder was already tracked as this profile; nothing changed.
    case alreadyAdded(Profile)
    /// The folder looks like neither a Claude nor a Codex config directory; nothing changed.
    case unrecognized
}

extension UsageStore {
    /// Adds a folder the user picked, detecting whether it belongs to Claude or Codex.
    /// Main actor; the folder's contents are inspected off it.
    public func addProfile(directory: String) async -> AddProfileOutcome {
        let fileSystem = dependencies.fileSystem
        let standard = ConfigPath.standardized(directory, home: fileSystem.homeDirectory)
        let detected = await Task.detached {
            ProfileDiscovery(fileSystem: fileSystem).provider(forDirectory: standard)
        }.value
        // Checked after the await so a folder added meanwhile is not added twice.
        if let existing = profiles.first(where: { standardized($0.configDirectory) == standard }) {
            return .alreadyAdded(existing)
        }
        guard let detected else {
            return .unrecognized
        }
        addProfile(provider: detected, directory: directory)
        candidates.removeAll { standardized($0.configDirectory) == standard }
        return profiles.first { standardized($0.configDirectory) == standard }.map { .added($0) } ?? .unrecognized
    }

    private func standardized(_ path: String) -> String {
        ConfigPath.standardized(path, home: dependencies.fileSystem.homeDirectory)
    }
}
