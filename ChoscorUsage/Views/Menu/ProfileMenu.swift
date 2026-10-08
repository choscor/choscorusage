// One profile in the menu: its logo, name and every window on a single row.
import ChoscorUsageKit
import SwiftUI

/// A flat row with the profile's name and windows (or problem) as its title. Choosing it toggles
/// whether the menu bar shows this row's usage (checked when it does) and runs the action that
/// fixes the profile's problem, if any; the full problem text is the tooltip.
struct ProfileMenu: View {
    let usage: ProfileUsage
    let item: ProfileMenuItem
    let isChosen: Bool
    let toggleChosen: () -> Void
    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        // A menu Toggle renders as an NSMenuItem with a checkmark state.
        Toggle(isOn: Binding(get: { isChosen }, set: { _ in perform() })) {
            Label {
                Text(item.rowTitle)
            } icon: {
                ProviderGlyph.image(for: usage.profile.provider)
            }
        }
        .help(item.message ?? "")
    }

    private func perform() {
        toggleChosen()
        switch item.action {
        case .retry: retry()
        case .openSettings: openSettings()
        case nil: break
        }
    }
}
