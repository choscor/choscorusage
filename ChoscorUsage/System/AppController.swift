// Wires the live Kit dependencies to OS integration: notifications, login item and wake events.
import AppKit
import ChoscorUsageKit

/// Owns the store and the OS glue for the app's lifetime.
@MainActor
@Observable
final class AppController {
    let store: UsageStore
    let launchAtLogin = LaunchAtLogin()
    @ObservationIgnored private let notifier = NotificationDelivery()
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        store = UsageStore(dependencies: .live(appVersion: version, notifier: notifier))
        observeWake()
        Task { await launch() }
    }

    /// Requests notification permission when the user turns an alert kind on.
    func notificationsToggled(_ enabled: Bool) {
        guard enabled else {
            return
        }
        Task { await notifier.requestAuthorization() }
    }

    private func launch() async {
        await store.start()
        if store.preferences.notificationsEnabled {
            await notifier.requestAuthorization()
        }
        store.startAutomaticRefresh()
    }

    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [store] _ in
            Task { @MainActor in await store.refresh(.wake) }
        }
    }
}
