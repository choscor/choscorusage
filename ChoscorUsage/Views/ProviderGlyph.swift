// The SF Symbol that identifies each provider in lists.
import ChoscorUsageKit

/// Provider glyphs; generic symbols rather than vendor logos.
enum ProviderGlyph {
    static func symbol(for provider: Provider) -> String {
        switch provider {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}
