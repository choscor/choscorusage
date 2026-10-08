// The menu bar item: a gauge glyph and the chosen profile's badge or worst percentage, tinted at 80% and 95%.
import AppKit
import ChoscorUsageKit
import SwiftUI

/// Menu bar labels render as templates, which drop colors, so tinted states are drawn into a
/// non-template image; the normal state stays a template and follows the menu bar appearance.
struct MenuBarLabel: View {
    let summary: MenuBarSummary

    var body: some View {
        Group {
            if let color = tint, let image = renderedTinted(color) {
                Image(nsImage: image)
            } else {
                content(color: nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private var tint: Color? {
        switch summary.tint {
        case .normal: nil
        case .warning: .orange
        case .critical: .red
        }
    }

    private func content(color: Color?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .accessibilityHidden(true)
            Text(summary.text)
                .monospacedDigit()
        }
        .foregroundStyle(color ?? .primary)
    }

    private func renderedTinted(_ color: Color) -> NSImage? {
        let renderer = ImageRenderer(content: content(color: color).font(.system(size: 13)))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }
}
