// The popover footer: Refresh, Settings… and Quit.
import AppKit
import ChoscorUsageKit
import SwiftUI

/// Footer actions. Refresh is debounced by the store.
struct PopoverFooter: View {
    let store: UsageStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Button {
                Task { await store.refresh(.manual) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            Spacer()
            Button("Settings…") {
                NSApplication.shared.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
