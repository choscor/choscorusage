// The inline message for a profile that is not fresh, with its Retry or Settings action.
import AppKit
import ChoscorUsageKit
import SwiftUI

/// Shows a warning glyph, the state's message, and the action that resolves it.
struct ProfileStateRow: View {
    let state: ProfileState
    let message: String
    let retry: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: state == .apiKeyMode ? "info.circle" : "exclamationmark.triangle")
                .foregroundStyle(state == .apiKeyMode ? Color.secondary : Color.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action
        }
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .keychainDenied:
            Button("Retry", action: retry)
                .controlSize(.small)
        case .keychainItemNotFound, .credentialsNotFound:
            Button("Open Settings") {
                NSApplication.shared.activate()
                openSettings()
            }
            .controlSize(.small)
        default:
            EmptyView()
        }
    }
}
