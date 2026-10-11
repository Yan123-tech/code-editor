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

    /// Diagnostics currently underlined in the active text view, so they can be cleared
    /// before applying a new batch without touching ranges the server didn't mention.
    private var renderedDiagnostics: [DocumentDiagnostic] = []

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
        clearDiagnosticUnderlines()
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
        clearDiagnosticUnderlines()
        await openIfNeeded()
        // If this document had diagnostics from a previous visit, re-render them.
        renderDiagnosticUnderlines(document.diagnostics)
    }

    // MARK: - Document sync

    /// `didOpen` on first appearance, for on-disk documents only (untitled docs have no
    /// URI; sourcekit-lsp can't anchor a position to them). Also subscribes to diagnostics
    /// for this document's URI.
    private func openIfNeeded() async {
        guard !didOpen, let url = document.url else { return }
        let uri = url.absoluteString
        guard let client = await appState?.languageServer(for: document.language.identifier),
            client.isReady
        else { return }
        currentURI = uri
        await client.openDocument(uri: uri, languageId: document.language.identifier, content: document.content)
        didOpen = true

        // Diagnostics for this URI are stored in the shared client, but the callback is
        // single — so it always points at whichever document opened most recently. The
        // active document is the common case; switching tabs re-renders from the stored
        // `document.diagnostics`.
        client.onDiagnosticsChanged = { [weak self] serverURI, serverDiagnostics in
            guard let self, serverURI == currentURI else { return }
            let converted = self.convertDiagnostics(serverDiagnostics)
            self.document.setDiagnostics(converted)
            self.renderDiagnosticUnderlines(converted)
        }
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

    // MARK: - Diagnostics

    /// Convert LSP `Diagnostic`s to the Core model. Uses UTF-8 offsets via
    /// `Document.offset(forLine:column:)` — correct for ASCII source (the common case
    /// for Swift), matching the same assumption as completion positions.
    private func convertDiagnostics(_ diagnostics: [Diagnostic]) -> [DocumentDiagnostic] {
        diagnostics.compactMap { diag in
            guard
                let start = document.offset(
                    forLine: diag.range.start.line, column: diag.range.start.character),
                let end = document.offset(
                    forLine: diag.range.end.line, column: diag.range.end.character)
            else { return nil }
            let severity: DocumentDiagnosticSeverity
            switch diag.severity {
            case .error: severity = .error
            case .warning: severity = .warning
            case .information: severity = .information
            case .hint: severity = .hint
            case .none: severity = .information
            }
            return DocumentDiagnostic(
                range: TextSelection(start: start, end: end),
                severity: severity,
                message: diag.message
            )
        }
    }

    /// Remove previously-rendered diagnostic underlines and paint the new set.
    /// Uses `.underlineStyle` + `.underlineColor` attributes on the text storage.
    /// Wavy squiggles are drawn by the upstream gutter/renderer; a solid colored
    /// underline is the MVP stand-in for the familiar compiler-error look.
    /// Gutter markers are a follow-up — the upstream `GutterView` has no marker API in 0.15.
    private func renderDiagnosticUnderlines(_ diagnostics: [DocumentDiagnostic]) {
        clearDiagnosticUnderlines()

        guard let storage = controller?.textView.textStorage else {
            renderedDiagnostics = diagnostics
            return
        }

        for diag in diagnostics {
            guard let range = document.nsRange(from: diag.range.start, to: diag.range.end) else { continue }
            let color = diagnosticColor(diag.severity)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.underlineColor, value: color, range: range)
        }
        renderedDiagnostics = diagnostics
    }

    /// Revert the text storage to its un-underlined state for the last rendered set.
    private func clearDiagnosticUnderlines() {
        guard let storage = controller?.textView.textStorage else { return }

        for diag in renderedDiagnostics {
            if let range = document.nsRange(from: diag.range.start, to: diag.range.end) {
                storage.removeAttribute(.underlineStyle, range: range)
                storage.removeAttribute(.underlineColor, range: range)
            }
        }
        renderedDiagnostics.removeAll()
    }

    /// The color for a diagnostic severity, drawn from `Theme.semantic` so the palette
    /// determines meaning (red = error, yellow = warning, green = info).
    private func diagnosticColor(_ severity: DocumentDiagnosticSeverity) -> NSColor {
        switch severity {
        case .error: return theme.semantic.danger.nsColor
        case .warning: return theme.semantic.warning.nsColor
        case .information: return theme.semantic.success.nsColor
        case .hint: return theme.secondaryText.nsColor
        }
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
