// One profile in the popover: name, glyph, age, its windows and any inline problem.
import ChoscorUsageKit
import SwiftUI

/// A profile header followed by its window rows and state message.
struct ProfileSectionView: View {
    let usage: ProfileUsage
    let now: Date
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(usage.snapshot?.windows ?? []) { window in
                UsageWindowRow(window: window, now: now)
            }
            if let message = usage.state.message {
                ProfileStateRow(state: usage.state, message: message, retry: retry)
            }
        }
    }

    private var header: some View {
        HStack {
            Label(usage.profile.displayName, systemImage: ProviderGlyph.symbol(for: usage.profile.provider))
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if let snapshot = usage.snapshot {
                Text(ageText(snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ageText(_ snapshot: UsageSnapshot) -> String {
        let age = CompactDuration.age(now.timeIntervalSince(snapshot.observedAt))
        if case .localLog = snapshot.source {
            return "from local log · \(age)"
        }
        return usage.state == .fresh ? "⟳ \(age)" : "last updated \(age)"
    }
}
