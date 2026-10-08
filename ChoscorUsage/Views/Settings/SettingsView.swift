// The Settings window: Profiles and General tabs.
import ChoscorUsageKit
import SwiftUI

/// Settings root.
struct SettingsView: View {
    let store: UsageStore
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        TabView {
            Tab("Profiles", systemImage: "person.2") {
                ProfilesSettingsView(store: store)
            }
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(store: store, launchAtLogin: launchAtLogin)
            }
        }
        .frame(width: 560, height: 420)
    }
}
