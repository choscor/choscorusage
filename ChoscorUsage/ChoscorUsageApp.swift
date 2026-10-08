// The app entry point: a menu bar extra with a native menu and a Settings scene.
import ChoscorUsageKit
import SwiftUI

@main
struct ChoscorUsageApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            UsageMenu(store: controller.store, now: controller.menuOpenedAt)
        } label: {
            MenuBarLabel(summary: controller.store.summary(at: controller.labelNow))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(store: controller.store, launchAtLogin: controller.launchAtLogin)
                .onChange(of: controller.store.preferences.notificationsEnabled) { _, enabled in
                    controller.notificationsToggled(enabled)
                }
        }
    }
}
