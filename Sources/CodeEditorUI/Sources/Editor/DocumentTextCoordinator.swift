import AppKit
import CodeEditorCore
import CodeEditSourceEditor
import CodeEditTextView

/// Keeps the text view's contents in step with the document it is showing and ensures
/// edits in the text view immediately mark the document modified.
///
/// `SourceEditor` pushes text into its text view in `makeNSViewController`.
/// Conforming to `TextViewDelegate` guarantees that every keystroke or character replacement
/// immediately updates `Document.content` and sets `isModified = true` synchronously.
@MainActor
final class DocumentTextCoordinator: TextViewCoordinator, TextViewDelegate {
    private weak var controller: TextViewController?
    private weak var document: CodeEditorCore.Document?

    init(document: CodeEditorCore.Document? = nil) {
        self.document = document
    }

    func updateDocument(_ document: CodeEditorCore.Document) {
        self.document = document
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        document?.setContent(textView.string)
    }

    /// Replace the editor's contents, unless it is already showing them.
    ///
    /// Safe either way: the change flows back through the binding, and `Document.setContent`
    /// guards on equality, so reloading the same text records no edit and no undo entry.
    func reload(text: String) {
        guard let controller, controller.textView.string != text else { return }
        controller.setText(text)
    }
}
