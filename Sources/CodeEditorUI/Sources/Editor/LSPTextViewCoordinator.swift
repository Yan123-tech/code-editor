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
    CodeSuggestionDelegate, JumpToDefinitionDelegate
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
        installMouseMonitor()
        Task {
            await openIfNeeded()
            renderDiagnosticUnderlines(document.diagnostics)
        }
    }

    func destroy() {
        removeMouseMonitor()
        controller = nil
        clearDiagnosticUnderlines()
    }

    func controllerDidDisappear(controller: TextViewController) {
        closeDiagnosticPopover()
    }

    // MARK: - Tab / workspace switch

    /// Switch the coordinator to a different document (tab switch): closes the previous
    /// document with the server and opens the new one.
    func switchTo(document: CodeEditorCore.Document) async {
        guard self.document !== document else { return }

        closeDiagnosticPopover()
        if let uri = currentURI,
            let client = await appState?.languageServer(for: document.language.identifier),
            client.isReady
        {
            await client.closeDocument(uri: uri)
        }

        clearDiagnosticUnderlines()
        self.document = document
        didOpen = false
        lastCompletionItems = nil
        crashShown = false
        currentURI = nil
        await openIfNeeded()
        // If this document had diagnostics from a previous visit, re-render them.
        renderDiagnosticUnderlines(document.diagnostics)
    }

    // MARK: - Document sync

    private func matchesCurrentURI(_ uri: String) -> Bool {
        guard let currentURI else { return false }
        if uri == currentURI { return true }
        guard let u1 = URL(string: uri), let u2 = URL(string: currentURI) else { return false }
        return u1.standardizedFileURL == u2.standardizedFileURL || u1.path == u2.path
    }

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
        // `document.diagnostics`. Dispatched to MainActor since UI underlines and Document
        // mutations require main thread execution.
        client.onDiagnosticsChanged = { [weak self] serverURI, serverDiagnostics in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.matchesCurrentURI(serverURI) else { return }
                let converted = self.convertDiagnostics(serverDiagnostics)
                self.document.setDiagnostics(converted)
                self.renderDiagnosticUnderlines(converted)
            }
        }

        // Render any cached diagnostics the client or document already has
        let cached = client.diagnostics(for: uri)
        if !cached.isEmpty {
            let converted = convertDiagnostics(cached)
            document.setDiagnostics(converted)
            renderDiagnosticUnderlines(converted)
        } else if !document.diagnostics.isEmpty {
            renderDiagnosticUnderlines(document.diagnostics)
        }
    }

    /// Forward a keystroke to the server, debounced so a fast typist sends one
    /// `didChange` per burst instead of one per character.
    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        closeDiagnosticPopover()
        guard controller != nil else { return }
        didChangeTask?.cancel()
        didChangeTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await openIfNeeded()
            guard !Task.isCancelled,
                let uri = self.currentURI ?? self.document.url?.absoluteString,
                let client = await self.appState?.languageServer(for: self.document.language.identifier),
                client.isReady
            else { return }
            await client.updateDocument(uri: uri, content: textView.string)
        }
    }

    // MARK: - CodeSuggestionDelegate

    func completionTriggerCharacters() -> Set<String> {
        [".", ":", "/", "@", "$", "_"]
    }

    /// Fetch completions at the caret, rank them, and present. A stale in-flight request
    /// is cancelled first so only the latest trigger wins.
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        completionGeneration += 1
        let generation = completionGeneration
        didChangeTask?.cancel()

        guard LanguageServerRegistry.descriptor(for: document.language.identifier) != nil else { return nil }
        guard let uri = document.url?.absoluteString else { return nil }
        guard let client = await appState?.languageServer(for: document.language.identifier),
            client.isReady
        else {
            let reason = appState?.errorMessage ?? "Language server could not start."
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
            guard !ranked.isEmpty else { return nil }
            let windowPos = CursorPosition(range: NSRange(location: caret, length: 0))
            return (windowPos, ranked)
        } catch {
            self.lastCompletionItems = nil
            guard generation == self.completionGeneration, !crashShown else { return nil }
            crashShown = true
            let message = (error as NSError).localizedDescription
            let reason = message.isEmpty ? "Language server stopped responding." : message
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

    // MARK: - JumpToDefinitionDelegate

    /// Builds a definition link at the hovered/⌘-clicked range. Also fetches a hover
    /// from the server so the link's `documentation` is populated — this gives the
    /// user both "go to definition" and a documentation tooltip inside the same popover.
    func queryLinks(
        forRange range: NSRange,
        textView: TextViewController
    ) async -> [JumpToDefinitionLink]? {
        guard let uri = currentURI,
            let client = await appState?.languageServer(for: document.language.identifier),
            client.isReady
        else { return nil }

        // The NSRange is an NSString index; for ASCII source that == UTF-16, so
        // `lspPosition(for:)` gives the same Position the server expects.
        guard let pos = document.lspPosition(for: range.location) else { return nil }

        let lspPos = CodeEditorLSP.Position(line: pos.line, character: pos.character)

        async let def = client.definition(at: lspPos, uri: uri)
        async let hover = client.hover(at: lspPos, uri: uri)

        guard let location = try? await def else {
            // No definition found — don't present a link (and don't beep).
            return nil
        }

        let hoverDoc = try? await hover?.contents.value
        return [link(from: location, hover: hoverDoc)]
    }

    /// Open a definition link in a different document.
    /// Same-document links (url == nil) are handled by the upstream `JumpToDefinitionModel`
    /// via `textView.selectionManager.setSelectedRange`, so this is only called for
    /// cross-file navigation.
    func openLink(link: JumpToDefinitionLink) {
        guard let url = link.url else { return }
        appState?.openFile(url)
    }

    // MARK: - Link building

    /// Convert an LSP `Location` to a `JumpToDefinitionLink`.
    /// - Same-file locations (uri == currentURI): `url = nil`, `targetRange` is an
    ///   `NSRange` computed from the document so the upstream can set the selection directly.
    /// - Cross-file locations: `url` is set; `targetRange` carries the LSP range as a
    ///   1-indexed `CursorPosition` for when the destination document loads.
    private func link(
        from location: Location,
        hover: String?
    ) -> JumpToDefinitionLink {
        if location.uri == currentURI {
            let start = document.offset(forLine: location.range.start.line, column: location.range.start.character)
            let end = document.offset(forLine: location.range.end.line, column: location.range.end.character)
            let range = NSRange(
                location: start ?? 0,
                length: max(0, (end ?? 0) - (start ?? 0))
            )
            return JumpToDefinitionLink(
                url: nil,
                targetRange: CursorPosition(range: range),
                typeName: "Definition",
                sourcePreview: " ",
                documentation: hover
            )
        }

        // Different file — the LSP URI may not be a standard file URL.
        let url = URL(string: location.uri)
        return JumpToDefinitionLink(
            url: url,
            targetRange: CursorPosition(
                start: .init(line: location.range.start.line + 1, column: location.range.start.character + 1),
                end: .init(line: location.range.end.line + 1, column: location.range.end.character + 1)
            ),
            typeName: url?.lastPathComponent ?? location.uri,
            sourcePreview: " ",
            documentation: hover
        )
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
                message: diag.message,
                source: diag.source
            )
        }
    }

    // MARK: - Diagnostic Underlines (EmphasisManager)

    static let diagnosticEmphasisGroupId = "lspDiagnostics"

    private func renderDiagnosticUnderlines(_ diagnostics: [DocumentDiagnostic]) {
        guard let tv = controller?.textView else {
            renderedDiagnostics = diagnostics
            return
        }

        guard let emphasisManager = tv.emphasisManager else {
            renderedDiagnostics = diagnostics
            return
        }

        let docLength = (tv.string as NSString).length
        guard docLength > 0 else {
            emphasisManager.removeEmphases(for: Self.diagnosticEmphasisGroupId)
            renderedDiagnostics = []
            return
        }

        let nsString = tv.string as NSString
        var emphases: [Emphasis] = []

        for diag in diagnostics {
            guard let range = document.nsRange(from: diag.range.start, to: diag.range.end) else { continue }
            guard range.location < docLength else { continue }

            var effectiveRange = range
            if effectiveRange.length == 0 {
                effectiveRange = expandedTokenRange(at: effectiveRange.location, in: nsString, docLength: docLength)
            } else if effectiveRange.location + effectiveRange.length > docLength {
                effectiveRange.length = docLength - effectiveRange.location
            }

            guard effectiveRange.length > 0 else { continue }

            let color = diagnosticColor(diag.severity)
            emphases.append(Emphasis(range: effectiveRange, style: .underline(color: color)))
        }

        emphasisManager.replaceEmphases(emphases, for: Self.diagnosticEmphasisGroupId)
        renderedDiagnostics = diagnostics
    }

    private func clearDiagnosticUnderlines() {
        guard let tv = controller?.textView else { return }
        tv.emphasisManager?.removeEmphases(for: Self.diagnosticEmphasisGroupId)
        renderedDiagnostics.removeAll()
    }

    private func expandedTokenRange(at location: Int, in string: NSString, docLength: Int) -> NSRange {
        guard location < docLength else {
            return NSRange(location: max(0, docLength - 1), length: min(1, docLength))
        }
        let underscore: UInt16 = 95
        func isIdentChar(_ code: UInt16) -> Bool {
            if code == underscore { return true }
            guard let scalar = UnicodeScalar(code) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        }
        let char = string.character(at: location)
        if !isIdentChar(char) {
            return NSRange(location: location, length: 1)
        }
        var start = location
        while start > 0 {
            let prev = string.character(at: start - 1)
            if isIdentChar(prev) {
                start -= 1
            } else {
                break
            }
        }
        var end = location
        while end < docLength {
            let next = string.character(at: end)
            if isIdentChar(next) {
                end += 1
            } else {
                break
            }
        }
        return NSRange(location: start, length: max(1, end - start))
    }

    // MARK: - Diagnostic Mouse Hover Popover

    private var mouseMonitor: Any?
    private var activePopover: NSPopover?
    private var hoveredDiagnosticRange: NSRange?

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        closeDiagnosticPopover()
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard let controller, let tv = controller.textView else { return }
        guard let window = tv.window, event.window === window else {
            closeDiagnosticPopover()
            return
        }

        let windowPoint = event.locationInWindow
        let viewPoint = tv.convert(windowPoint, from: nil)
        guard tv.bounds.contains(viewPoint) else {
            closeDiagnosticPopover()
            return
        }

        let stringLength = (tv.string as NSString).length
        guard stringLength > 0 else {
            closeDiagnosticPopover()
            return
        }

        guard let offset = tv.layoutManager.textOffsetAtPoint(viewPoint),
            offset < stringLength
        else {
            closeDiagnosticPopover()
            return
        }

        let matchingDiagnostics = document.diagnostics.filter { diag in
            guard let range = document.nsRange(from: diag.range.start, to: diag.range.end) else { return false }
            if range.contains(offset) || (range.length == 0 && range.location == offset) {
                return true
            }
            if let diagLine = document.lineAndColumn(for: range.location)?.line,
                let currentLine = document.lineAndColumn(for: offset)?.line,
                diagLine == currentLine
            {
                return true
            }
            return false
        }

        guard !matchingDiagnostics.isEmpty else {
            closeDiagnosticPopover()
            return
        }

        guard let firstDiag = matchingDiagnostics.first,
            let anchorRange = document.nsRange(from: firstDiag.range.start, to: firstDiag.range.end)
        else {
            closeDiagnosticPopover()
            return
        }

        if hoveredDiagnosticRange == anchorRange && activePopover?.isShown == true {
            return
        }

        showDiagnosticPopover(for: matchingDiagnostics, anchorRange: anchorRange, at: viewPoint, in: tv)
    }

    private func showDiagnosticPopover(
        for diagnostics: [DocumentDiagnostic],
        anchorRange: NSRange,
        at point: CGPoint,
        in tv: TextView
    ) {
        closeDiagnosticPopover()

        hoveredDiagnosticRange = anchorRange

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let popoverView = DiagnosticPopoverView(diagnostics: diagnostics, theme: theme)
        let hostingController = NSHostingController(rootView: popoverView)
        popover.contentViewController = hostingController

        let anchorRect: NSRect
        if let rect = tv.layoutManager.rectsFor(range: anchorRange).first {
            anchorRect = rect
        } else {
            anchorRect = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        }

        popover.show(relativeTo: anchorRect, of: tv, preferredEdge: .maxY)
        self.activePopover = popover
    }

    private func closeDiagnosticPopover() {
        if let popover = activePopover {
            popover.close()
            activePopover = nil
        }
        hoveredDiagnosticRange = nil
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
        if cursorPosition.range != .notFound {
            return cursorPosition.range.location
        }
        guard cursorPosition.start.line > 0, cursorPosition.start.column > 0 else { return nil }
        return document.offset(
            forLine: cursorPosition.start.line - 1,
            column: cursorPosition.start.column - 1
        )
    }
}
