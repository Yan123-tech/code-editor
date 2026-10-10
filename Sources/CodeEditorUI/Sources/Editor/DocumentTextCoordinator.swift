import CodeEditSourceEditor

/// Keeps the text view's contents in step with the document it is showing.
///
/// `SourceEditor` pushes text into its text view exactly once, in
/// `makeNSViewController`. `updateNSViewController` diffs language, configuration and
/// highlight providers — **it never diffs the text behind the `Binding<String>`**. Switching
/// tabs therefore leaves the previously opened document on screen, and every tab shows the
/// same file.
///
/// `prepareCoordinator` is the one hook that hands out the live controller, and it runs once
/// per controller, so this holds it weakly and `CodeEditorView` calls `reload(text:)` when
/// the document changes.
///
/// This is a workaround for upstream, not a design preference. If a future version diffs the
/// text on update, this type should go away — see [MEMORY.md](../../../docs/MEMORY.md).
@MainActor
final class DocumentTextCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
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
