// The Claude and Codex logos that identify each provider in menus and lists.
import AppKit
import ChoscorUsageKit
import SwiftUI

/// Provider logos from the asset catalog (Simple Icons' Claude and OpenAI marks; Codex has no
/// mark of its own), drawn in each brand's color. The marks belong to Anthropic and OpenAI;
/// ChoscorUsage is unaffiliated.
@MainActor
enum ProviderGlyph {
    private static let claude = makeImage(for: .claude)
    private static let codex = makeImage(for: .codex)

    /// The provider's logo, built once per provider.
    static func image(for provider: Provider) -> Image {
        switch provider {
        case .claude: claude
        case .codex: codex
        }
    }

    /// Menu items draw an `NSImage` at its own size and ignore SwiftUI frames and tints, so the
    /// 24 pt vector is redrawn at the 16 pt menu icon size, filled with the brand color.
    private static func makeImage(for provider: Provider) -> Image {
        guard let logo = NSImage(named: assetName(for: provider)) else {
            return Image(systemName: "questionmark.circle")
        }
        return Image(nsImage: tinted(logo, brandColor(for: provider)))
    }

    /// Nonisolated because AppKit may call an image's drawing handler on whatever thread draws
    /// it; a main-actor-isolated closure would trap there.
    private nonisolated static func tinted(_ logo: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            logo.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func assetName(for provider: Provider) -> String {
        switch provider {
        case .claude: "ClaudeLogo"
        case .codex: "CodexLogo"
        }
    }

    /// Simple Icons' brand hex values: Claude `#D97757`, OpenAI `#412991`
    /// (https://github.com/simple-icons/simple-icons, data/simple-icons.json, verified 2026-10-08).
    private static func brandColor(for provider: Provider) -> NSColor {
        switch provider {
        case .claude: NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
        case .codex: NSColor(srgbRed: 0x41 / 255, green: 0x29 / 255, blue: 0x91 / 255, alpha: 1)
        }
    }
}
