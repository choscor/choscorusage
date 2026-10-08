// Confirms discovered profiles in an alert, since a menu closes before it can show results.
import AppKit
import ChoscorUsageKit

/// Presents the store's pending candidates for confirmation, or says that the scan found none.
@MainActor
enum ProfileScanAlert {
    /// Runs a modal alert. Confirming adds the candidates shown; any other answer dismisses only
    /// those, so a rescan that finished while the alert was open stays pending.
    static func present(for store: UsageStore) {
        let candidates = store.candidates
        let prompt = ProfileScanPrompt.make(for: candidates)
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        if let confirm = prompt.confirmTitle {
            alert.addButton(withTitle: confirm)
            alert.addButton(withTitle: "Not Now")
        } else {
            alert.addButton(withTitle: "OK")
        }
        NSApplication.shared.activate()
        let response = alert.runModal()
        guard prompt.confirmTitle != nil else {
            return
        }
        if response == .alertFirstButtonReturn {
            store.add(candidates)
        } else {
            store.dismiss(candidates)
        }
    }
}
