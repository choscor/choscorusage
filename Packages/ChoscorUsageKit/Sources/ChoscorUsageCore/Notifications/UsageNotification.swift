// A notification the app should deliver, holding only display-safe text.

/// A threshold or reset alert. Text holds only the display name, window label and percentage.
public struct UsageNotification: Equatable, Sendable {
    /// Stable identifier, unique per profile, window, reset time and kind.
    public let id: String
    /// The profile's display name.
    public let title: String
    /// For example `5h window at 82%` or `5h window reset`.
    public let body: String

    /// Creates a notification.
    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}
