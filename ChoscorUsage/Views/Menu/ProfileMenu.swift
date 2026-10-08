// One profile in the menu: its logo, name and every window on a single row.
import ChoscorUsageKit
import SwiftUI

/// A flat row with the profile's windows (or problem) as a trailing badge. Choosing it runs the
/// action that fixes the profile's problem, if any; the full problem text is the tooltip.
struct ProfileMenu: View {
    let usage: ProfileUsage
    let item: ProfileMenuItem
    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        Button(action: perform) {
            Label {
                Text(item.title)
            } icon: {
                ProviderGlyph.image(for: usage.profile.provider)
            }
        }
        .badge(Text(item.badge))
        .help(item.message ?? "")
    }

    private func perform() {
        switch item.action {
        case .retry: retry()
        case .openSettings: openSettings()
        case nil: break
        }
    }
}
