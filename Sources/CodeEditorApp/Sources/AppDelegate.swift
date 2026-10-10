import AppKit
import CodeEditorCore
import CodeEditorUI

/// Guards unsaved work on quit.
///
/// Without this the app quits unconditionally and unsaved edits are gone without a word —
/// the only remaining path to data loss in the app.
///
/// **Why `NSAlert` and not a SwiftUI `.alert`.** `applicationShouldTerminate` must return
/// synchronously, and the answer `terminateCancel` is what stops the quit. A SwiftUI alert
/// bound to view state can do neither: the decision has to be made before the app tears down,
/// with no view tree to attach to. Every other dialog in this app is SwiftUI; this one is not,
/// and it is not a regression of that.
///
/// The re-entrancy flag matters: after the user answers, the delegate calls `NSApp.terminate`
/// again, which lands back here. Without the flag the prompt would reappear forever.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the scene once `AppState` exists. Nil means "no state yet", which is treated
    /// as "nothing to lose" rather than blocking quit on an unanswerable question.
    var appState: AppState?

    private var isResolvingTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isResolvingTermination, let appState else { return .terminateNow }

        let modified = appState.documentManager.documents.filter(\.isModified)
        guard !modified.isEmpty else { return .terminateNow }

        isResolvingTermination = true
        Task { await resolveTermination(modified, for: sender) }
        return .terminateCancel
    }

    // MARK: - Resolution

    private func resolveTermination(
        _ modified: [CodeEditorCore.Document],
        for sender: NSApplication
    ) async {
        switch prompt(for: modified) {
        case .save:
            // A cancelled panel on an untitled document means the work is still there.
            // Abandoning the quit is the only way not to throw it away.
            if await appState?.saveAllModified() == true {
                sender.terminate(nil)
            } else {
                isResolvingTermination = false
            }
        case .discard:
            sender.terminate(nil)
        case .cancel:
            isResolvingTermination = false
        }
    }

    private enum Choice {
        case save
        case discard
        case cancel
    }

    private func prompt(for modified: [CodeEditorCore.Document]) -> Choice {
        let alert = NSAlert()
        if modified.count == 1, let only = modified.first {
            alert.messageText = "Save changes to \(only.name)?"
        } else {
            alert.messageText = "Save changes to \(modified.count) documents?"
        }
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}
