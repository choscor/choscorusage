// Lets the user pick which `Claude Code-credentials*` Keychain item a Claude profile uses.
import ChoscorUsageKit
import SwiftUI

/// Shown when the computed Keychain item is missing. Lists services by attributes only, which
/// never prompts; the chosen name is saved as the profile's override.
struct KeychainItemPicker: View {
    let store: UsageStore
    let profile: Profile
    @State private var services: [String] = []

    var body: some View {
        HStack {
            if profile.keychainServiceOverride == nil {
                Text("Keychain item not found")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Picker("Keychain item", selection: selection) {
                Text("Automatic").tag(String?.none)
                ForEach(services, id: \.self) { service in
                    Text(service).tag(Optional(service))
                }
            }
            .fixedSize()
        }
        .task { services = await store.keychainServiceNames() }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { profile.keychainServiceOverride },
            set: { service in Task { await store.setKeychainOverride(profile.id, service: service) } })
    }
}
