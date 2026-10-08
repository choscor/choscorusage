// The native menu bar menu: profiles, then add, scan, refresh, Settings and Quit.
import AppKit
import ChoscorUsageKit
import SwiftUI

/// Menu content for the `.menu`-style `MenuBarExtra`. AppKit renders it as an `NSMenu`, so every
/// row is a plain item; each profile fits on one row and one row says when data was updated.
struct UsageMenu: View {
    let store: UsageStore
    /// When the menu last opened; countdowns are measured from it because menus do not tick.
    let now: Date
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ProfilesSection(store: store, now: now, openSettings: showSettings)
        Divider()
        Button("Add Profile…", systemImage: "plus") {
            Task { await ProfileDirectoryPicker.pick(store: store) }
        }
        Button("Scan for Profiles…", systemImage: "magnifyingglass") {
            Task {
                await store.rescan()
                ProfileScanAlert.present(for: store)
            }
        }
        Divider()
        Button(store.isRefreshing ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise") {
            Task { await store.refresh(.manual) }
        }
        .keyboardShortcut("r")
        .disabled(store.isRefreshing)
        // An icon puts the text in the title column; an icon-less item starts in the icon column.
        if let updated = ProfileMenuItem.lastUpdated(store.visibleUsages, now: now) {
            Label(updated, systemImage: "clock")
        }
        Divider()
        Button("Settings…", systemImage: "gearshape", action: showSettings)
            .keyboardShortcut(",")
        Divider()
        Button("Quit ChoscorUsage", systemImage: "power") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showSettings() {
        NSApplication.shared.activate()
        openSettings()
    }
}

/// One row per visible profile, a review item for pending candidates, or an empty state.
private struct ProfilesSection: View {
    let store: UsageStore
    let now: Date
    let openSettings: () -> Void

    var body: some View {
        if let review = ProfileScanPrompt.make(for: store.candidates).menuTitle {
            Button(review, systemImage: "sparkle.magnifyingglass") { ProfileScanAlert.present(for: store) }
        }
        if store.visibleUsages.isEmpty {
            Text("No Profiles")
        }
        ForEach(store.visibleUsages) { usage in
            ProfileMenu(
                usage: usage, item: ProfileMenuItem.make(from: usage, now: now),
                isChosen: store.chosenProfileID == usage.id,
                toggleChosen: { store.toggleChosenProfile(usage.id) },
                retry: { Task { await store.retry(usage.id) } }, openSettings: openSettings)
        }
    }
}
