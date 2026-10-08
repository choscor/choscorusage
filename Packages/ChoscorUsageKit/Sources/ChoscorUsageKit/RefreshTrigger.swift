// The events that can start a refresh.

/// Why a refresh was requested.
public enum RefreshTrigger: Sendable {
    /// App launch.
    case launch
    /// The automatic interval elapsed.
    case timer
    /// The popover's Refresh button.
    case manual
    /// The popover opened.
    case popoverOpened
    /// The Mac woke from sleep.
    case wake
    /// The user pressed Retry on a profile that needs Keychain access.
    case retry
}
