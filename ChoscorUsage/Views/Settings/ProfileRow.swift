// One editable profile row: name field, path, hide toggle and Keychain-item picker.
import ChoscorUsageKit
import SwiftUI

/// Rename, hide and (for Claude) choose a Keychain item for one profile.
struct ProfileRow: View {
    let store: UsageStore
    let usage: ProfileUsage
    @State private var name = ""
    @FocusState private var isEditingName: Bool

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: ProviderGlyph.symbol(for: usage.profile.provider))
                .accessibilityLabel(usage.profile.provider.displayName)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name)
                    .focused($isEditingName)
                    .onSubmit(commitName)
                    .onChange(of: isEditingName) { _, editing in
                        if !editing {
                            commitName()
                        }
                    }
                Text(usage.profile.configDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if usage.profile.provider == .claude,
                    usage.state == .keychainItemNotFound
                        || usage.profile.keychainServiceOverride != nil
                {
                    KeychainItemPicker(store: store, profile: usage.profile)
                }
            }
            Toggle(
                "Hidden",
                isOn: Binding(get: { usage.profile.isHidden }, set: { store.setHidden(usage.id, $0) }))
        }
        .onAppear { name = usage.profile.displayName }
        .onChange(of: usage.profile.displayName) { _, newValue in name = newValue }
    }

    /// Saves the edited name; a blank name is rejected and the field shows the current name again.
    private func commitName() {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines) != usage.profile.displayName else {
            name = usage.profile.displayName
            return
        }
        store.rename(usage.id, to: name)
        name = store.profiles.first { $0.id == usage.id }?.displayName ?? usage.profile.displayName
    }
}
