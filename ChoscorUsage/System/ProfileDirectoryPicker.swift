// Asks the user for a Claude or Codex config folder and adds it as a profile.
import AppKit
import ChoscorUsageKit

/// The open panel shared by the menu's Add Profile item and the Settings Profiles tab.
@MainActor
enum ProfileDirectoryPicker {
    /// Shows a folder picker starting in the home folder, with hidden folders visible because
    /// config directories such as `~/.claude` are dot-folders. The store detects the provider;
    /// a folder it cannot place, or one already added, is explained in an alert.
    static func pick(store: UsageStore) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(filePath: NSHomeDirectory())
        panel.message = "Choose a Claude Code or Codex config folder, such as ~/.claude or ~/.codex."
        panel.prompt = "Add Profile"
        // A menu bar–only app is not active when its menu closes; without this the panel opens
        // behind other windows.
        NSApplication.shared.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        switch await store.addProfile(directory: url.path(percentEncoded: false)) {
        case .added:
            break
        case .alreadyAdded(let profile):
            showAlert("Already Added", "This folder is already the profile “\(profile.displayName)”.")
        case .unrecognized:
            showAlert(
                "Not a Claude or Codex Folder",
                "ChoscorUsage could not find Claude Code or Codex files in this folder. "
                    + "Choose the folder that holds settings.json or auth.json, such as ~/.claude or ~/.codex.")
        }
    }

    private static func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
