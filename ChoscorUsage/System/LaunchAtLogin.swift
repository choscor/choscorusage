// Launch-at-login toggle backed by SMAppService.mainApp, reporting the real status.
import Foundation
import ServiceManagement
import os

/// The login item state as macOS reports it.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?
    private static let logger = Logger(subsystem: "com.choscor.ChoscorUsage", category: "login-item")

    /// Whether the app is registered (enabled or awaiting approval).
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// Text describing the status, shown under the toggle.
    var statusText: String? {
        switch status {
        case .requiresApproval: "Requires approval in System Settings › General › Login Items."
        case .notFound: "Unavailable for this copy of the app."
        default: lastError
        }
    }

    /// Registers or unregisters the main app and re-reads the status.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    /// Re-reads the status, for example after the user returns from System Settings.
    func refresh() {
        status = SMAppService.mainApp.status
    }

    /// Opens System Settings at Login Items.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
