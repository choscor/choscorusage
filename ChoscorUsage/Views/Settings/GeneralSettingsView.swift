// General settings: refresh interval, launch at login and notification toggles.
import ChoscorUsageKit
import SwiftUI

/// The General tab.
struct GeneralSettingsView: View {
    @Bindable var store: UsageStore
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Picker("Refresh every", selection: $store.preferences.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text("\(interval.rawValue) minute\(interval.rawValue == 1 ? "" : "s")").tag(interval)
                }
            }
            LaunchAtLoginSection(launchAtLogin: launchAtLogin)
            Section("Notifications") {
                Toggle("Alert at 80% and 95% of a window", isOn: $store.preferences.thresholdAlertsEnabled)
                Toggle("Alert when a window that reached 80% resets", isOn: $store.preferences.resetAlertsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

/// The launch-at-login toggle with the real SMAppService status.
private struct LaunchAtLoginSection: View {
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Section {
            Toggle(
                "Launch at login",
                isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
            if let status = launchAtLogin.statusText {
                HStack {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if launchAtLogin.status == .requiresApproval {
                        Button("Open Login Items") { launchAtLogin.openSystemSettings() }
                    }
                }
            }
        }
        .onAppear { launchAtLogin.refresh() }
    }
}
