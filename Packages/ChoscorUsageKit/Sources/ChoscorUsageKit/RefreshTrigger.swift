// The events that can start a refresh.

/// Why a refresh was requested.
public enum RefreshTrigger: Sendable {
    /// App launch.
    case launch
    /// The automatic interval elapsed.
    case timer
    /// The menu's Refresh Now item.
    case manual
    /// The menu bar menu opened.
    case menuOpened
    /// The Mac woke from sleep.
    case wake
    /// The user pressed Retry on a profile that needs Keychain access.
    case retry

    /// Whether the user asked for this refresh, which lets a Claude credential read fall back
    /// to a direct Keychain read that may prompt. Automatic triggers never prompt.
    public var isUserAction: Bool {
        switch self {
        case .manual, .retry: true
        case .launch, .timer, .menuOpened, .wake: false
        }
    }
}
