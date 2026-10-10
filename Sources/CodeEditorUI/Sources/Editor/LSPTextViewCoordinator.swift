import CodeEditSourceEditor
import CodeEditTextView
import CodeEditorCore
import CodeEditorLSP
import CodeEditorThemes
import SwiftUI

/// A `CodeSuggestionEntry` backed by a single LSP `CompletionItem`, plus a sentinel
/// "error" entry that renders an inline crash/no-server message in the popup.
@MainActor
final class LSPCompletionItem: CodeSuggestionEntry {
    /// The source `CompletionItem`. `nil` for the synthetic error entry.
    let completionItem: CompletionItem?
    let isError: Bool
    private let fallbackLabel: String?

    init(_ item: CompletionItem) {
        self.completionItem = item
        self.isError = false
        self.fallbackLabel = nil
    }

    init(error message: String) {
        self.completionItem = nil
        self.isError = true
        self.fallbackLabel = message
    }

    // MARK: - CodeSuggestionEntry

    var label: String { completionItem?.label ?? fallbackLabel ?? "error" }
    var detail: String? {
        completionItem?.detail ?? (isError ? "SourceKit-LSP" : nil)
    }

    var documentation: String? { completionItem?.documentation?.value }
    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }

    var image: Image { Image(systemName: iconSymbol) }
    var imageColor: Color { isError ? .red : iconColor }
    var deprecated: Bool { false }

    // MARK: - Icons

    private var iconSymbol: String {
        guard let kind = completionItem?.kind else { return "curlybraces" }
        switch kind {
        case .method: return "chevron.left.slash.chevron.right"
        case .function, .constructor: return "function"
        case .class: return "cube"
        case .interface: return "cube.transparent"
        case .enum: return "cube.fill"
        case .module: return "folder"
        case .property: return "key.rhs"
        case .field: return "tag"
        case .variable, .constant: return "cube"
        case .value: return "number"
        case .keyword: return "textformat"
        case .file: return "doc"
        case .folder: return "folder"
        case .reference: return "book"
        case .unit: return "123"
        default: return "curlybraces"
        }
    }

    private var iconColor: Color {
        guard let kind = completionItem?.kind else { return .secondary }
        switch kind {
        case .function, .method, .constructor: return .orange
        case .class, .interface, .enum: return .purple
        case .keyword: return .blue
        case .variable, .constant, .field, .property: return .green
        case .value, .unit: return .red
        case .module, .file, .folder, .reference: return .secondary
        default: return .secondary
        }
    }
}

// MARK: - Coordinator

/// Wires a language server into a `TextViewController` so completions and edits flow to it.
///
/// The upstream `SuggestionController` owns the popup chrome and keyboard handling
/// (Escape to close, ↑/↓/Tab/Enter to accept, double-click). It only calls into this
/// coordinator through `CodeSuggestionDelegate` for the items and the apply step — no
/// bespoke SwiftUI popup is needed, see [docs/MEMORY.md](../../../docs/MEMORY.md).
@MainActor
final class LSPTextViewCoordinator: TextViewCoordinator, TextViewDelegate,
    CodeSuggestionDelegate
{
    private weak var controller: TextViewController?
    private let theme: Theme
    private weak var appState: AppState?

    private var document: CodeEditorCore.Document
    private var didOpen = false
    private var currentURI: String?

    /// Items from the most recent successful completion request, for prefix re-filtering
    /// on cursor move without another round-trip.
    private var lastCompletionItems: [CompletionItem]?
    /// Increments with each in-flight request; responses from a previous generation are
    /// discarded so a slow server can't paint a newer popup with stale items.
    private var completionGeneration = 0
    private var crashShown = false

    /// Coalesces rapid edits into a single `textDocument/didChange` per burst.
    private var didChangeTask: Task<Void, Never>?

    init(document: CodeEditorCore.Document, theme: Theme, appState: AppState) {
        self.document = document
        self.theme = theme
        self.appState = appState
    }

    // MARK: - TextViewCoordinator

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        Task { await openIfNeeded() }
    }

    func destroy() {
        controller = nil
    }

    // MARK: - Tab / workspace switch

    /// Switch the coordinator to a different document (tab switch): closes the previous
    /// document with the server and opens the new one.
    func switchTo(document: CodeEditorCore.Document) async {
        guard self.document !== document else { return }

        if let uri = currentURI,
            let client = await appState?.languageServer(for: document.language.identifier),
            client.isReady
        {
            await client.closeDocument(uri: uri)
        }

        self.document = document
        didOpen = false
        lastCompletionItems = nil
        crashShown = false
        currentURI = nil
        await openIfNeeded()
    }

    // MARK: - Document sync

    /// `didOpen` on first appearance, for on-disk documents only (untitled docs have no
    /// URI; sourcekit-lsp can't anchor a position to them).
    private func openIfNeeded() async {
        guard !didOpen, let url = document.url else { return }
        let uri = url.absoluteString
        guard let client = await appState?.languageServer(for: document.language.identifier),
            client.isReady
        else { return }
        currentURI = uri
        await client.openDocument(uri: uri, languageId: document.language.identifier, content: document.content)
        didOpen = true
    }

    /// Forward a keystroke to the server, debounced so a fast typist sends one
    /// `didChange` per burst instead of one per character.
    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        guard controller != nil else { return }
        didChangeTask?.cancel()
        didChangeTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled,
                let uri = self.currentURI,
                let client = await self.appState?.languageServer(for: self.document.language.identifier),
                client.isReady
            else { return }
            await client.updateDocument(uri: uri, content: textView.string)
        }
    }

    // MARK: - CodeSuggestionDelegate

    func completionTriggerCharacters() -> Set<String> { ["."] }

    /// Fetch completions at the caret, rank them, and present. A stale in-flight request
    /// is cancelled first so only the latest trigger wins.
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        completionGeneration += 1
        let generation = completionGeneration
        didChangeTask?.cancel()

        // Only on-disk Swift documents have a server; anything else stays quiet.
        guard LanguageServerRegistry.descriptor(for: document.language.identifier) != nil else { return nil }
        guard let uri = document.url?.absoluteString else { return nil }
        guard let client = await appState?.languageServer(for: document.language.identifier),
            client.isReady
        else {
            // `languageServer(for:)` already set `errorMessage` to a user-facing reason.
            let reason = appState?.errorMessage ?? "SourceKit-LSP could not start."
            return (cursorPosition, [LSPCompletionItem(error: reason)])
        }

        guard let caret = offset(for: cursorPosition),
            let pos = document.lspPosition(for: caret)
        else { return nil }

        do {
            let items = try await client.completion(
                at: CodeEditorLSP.Position(line: pos.line, character: pos.character), uri: uri
            )
            guard generation == self.completionGeneration else { return nil }
            self.lastCompletionItems = items
            self.crashShown = false
            let query = document.completionPrefix(at: caret)
            let ranked = rankedCompletions(items, query: query).map(LSPCompletionItem.init)
            return (cursorPosition, ranked)
        } catch {
            self.lastCompletionItems = nil
            guard generation == self.completionGeneration, !crashShown else { return nil }
            crashShown = true
            let message = (error as NSError).localizedDescription
            let reason = message.isEmpty ? "SourceKit-LSP stopped responding." : message
            return (cursorPosition, [LSPCompletionItem(error: reason)])
        }
    }

    /// Re-filter the last results to the new caret prefix. Returning `nil` closes the popup.
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard let items = lastCompletionItems, !items.isEmpty else { return nil }
        guard let caret = offset(for: cursorPosition) else { return nil }
        let prefix = document.completionPrefix(at: caret)
        guard !prefix.isEmpty else { return nil }
        let ranked = rankedCompletions(items, query: prefix).map(LSPCompletionItem.init)
        return ranked.isEmpty ? nil : ranked
    }

    /// Replace the identifier prefix (or the `TextEdit` range) with the item's
    /// `insertionText`. The text view advances the caret and the binding writes the
    /// new content back into the `Document`, so the document stays the single source
    /// of truth and no view reload is required.
    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let entry = item as? LSPCompletionItem, !entry.isError,
            let completionItem = entry.completionItem,
            let tv = controller?.textView
        else { return }

        let ns = tv.string as NSString
        let caret = offset(for: cursorPosition) ?? ns.length

        let range: NSRange
        if let textEdit = completionItem.textEdit {
            let startPosition = textEdit.range.start
            let endPosition = textEdit.range.end
            let start = document.offset(forLine: startPosition.line, column: startPosition.character) ?? caret
            let end = document.offset(forLine: endPosition.line, column: endPosition.character) ?? caret
            range = NSRange(location: start, length: max(0, end - start))
        } else if let prefixRange = document.completionPrefixRange(at: caret) {
            range = prefixRange
        } else {
            range = NSRange(location: caret, length: 0)
        }

        tv.replaceCharacters(in: range, with: completionItem.insertionText)
    }

    func completionWindowDidClose() {
        lastCompletionItems = nil
        crashShown = false
    }

    // MARK: - Helpers

    /// 1-indexed `CursorPosition` → UTF-8 content offset (ASCII source: == UTF-16).
    private func offset(for cursorPosition: CursorPosition?) -> Int? {
        guard let cursorPosition else { return nil }
        return document.offset(
            forLine: cursorPosition.start.line - 1,
            column: cursorPosition.start.column - 1
        )
    }
}
