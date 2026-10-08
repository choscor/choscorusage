// The app entry point: a menu bar extra with a popover window and a Settings scene.
import ChoscorUsageKit
import SwiftUI

@main
struct ChoscorUsageApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: controller.store)
        } label: {
            MenuBarLabel(summary: controller.store.summary)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: controller.store, launchAtLogin: controller.launchAtLogin)
                .onChange(of: controller.store.preferences.notificationsEnabled) { _, enabled in
                    controller.notificationsToggled(enabled)
                }
        }
    }
}
