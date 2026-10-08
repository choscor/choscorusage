// The Profiles tab: reorder, rename, hide, remove, add, rescan and confirm candidates.
import AppKit
import ChoscorUsageKit
import SwiftUI

/// Profile management.
struct ProfilesSettingsView: View {
    let store: UsageStore
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $selection) {
                ForEach(store.usages) { usage in
                    ProfileRow(store: store, usage: usage)
                        .tag(usage.id)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            if !store.candidates.isEmpty {
                CandidatesBanner(store: store)
            }
            ProfilesToolbar(store: store, selection: $selection)
        }
        .padding()
    }
}

/// Add, remove and rescan controls under the profile list.
private struct ProfilesToolbar: View {
    let store: UsageStore
    @Binding var selection: UUID?

    var body: some View {
        HStack {
            Menu("Add…") {
                ForEach(Provider.allCases, id: \.self) { provider in
                    Button("\(provider.displayName) config directory…") { pickDirectory(for: provider) }
                }
            }
            .fixedSize()
            Button("Remove") {
                if let selection {
                    store.remove(selection)
                }
                selection = nil
            }
            .disabled(selection == nil)
            Spacer()
            Button("Rescan") { Task { await store.rescan() } }
        }
    }

    private func pickDirectory(for provider: Provider) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(filePath: NSHomeDirectory())
        panel.prompt = "Add \(provider.displayName) Profile"
        if panel.runModal() == .OK, let url = panel.url {
            store.addProfile(provider: provider, directory: url.path(percentEncoded: false))
        }
    }
}
