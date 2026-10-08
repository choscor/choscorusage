// Wires the live Kit dependencies to OS integration: notifications, login item, wake and menu events.
import AppKit
import ChoscorUsageKit

/// Owns the store and the OS glue for the app's lifetime.
@MainActor
@Observable
final class AppController {
    let store: UsageStore
    let launchAtLogin = LaunchAtLogin()
    /// When a menu last began tracking; the menu measures countdowns and ages from it.
    private(set) var menuOpenedAt = Date.now
    /// The time the menu bar label measures countdowns from, advanced every minute.
    private(set) var labelNow = Date.now
    @ObservationIgnored private var labelTicker: Task<Void, Never>?
    @ObservationIgnored private let notifier = NotificationDelivery()
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var menuObserver: (any NSObjectProtocol)?

    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        store = UsageStore(dependencies: .live(appVersion: version, notifier: notifier))
        observeWake()
        observeMenuOpening()
        tickLabel()
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

    /// A chosen profile's badge shows reset countdowns, and the label only redraws when observed
    /// state changes, so the clock is advanced at the countdowns' one-minute resolution.
    private func tickLabel() {
        weak let controller = self
        labelTicker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                controller?.labelNow = .now
            }
        }
    }

    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [store] _ in
            Task { @MainActor in await store.refresh(.wake) }
        }
    }

    /// SwiftUI gives `.menu`-style menu bar extras no open callback, so the app watches AppKit's
    /// menu tracking. Other menus (such as Settings pickers) also post it; the scheduler only
    /// refreshes data older than 60 s, so those extra triggers are harmless.
    private func observeMenuOpening() {
        let center = NotificationCenter.default
        menuObserver = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in await self?.menuOpened() }
        }
    }

    private func menuOpened() async {
        menuOpenedAt = .now
        await store.refresh(.menuOpened)
    }
}
