// One usage window: label, progress bar, percentage and time until reset.
import ChoscorUsageKit
import SwiftUI

/// A row such as `5h ███░░ 72% ↻ 1h12m`, tinted at 80% and 95%.
struct UsageWindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.callout)
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)
            ProgressView(value: window.usedPercent, total: 100)
                .tint(tint)
                .accessibilityHidden(true)
            Text("\(Int(window.usedPercent.rounded(.down)))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Text(resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 56, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var tint: Color {
        switch MenuBarSummary.tint(for: window.usedPercent) {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }

    private var resetText: String {
        window.resetsAt.map { "↻ \(CompactDuration.format($0.timeIntervalSince(now)))" } ?? ""
    }

    private var accessibilityText: String {
        let percent = Int(window.usedPercent.rounded(.down))
        let reset = window.resetsAt.map { ", resets in \(CompactDuration.format($0.timeIntervalSince(now)))" } ?? ""
        return "\(window.label) window \(percent) percent used\(reset)"
    }
}
