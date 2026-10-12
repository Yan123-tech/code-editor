import CodeEditSourceEditor
import CodeEditTextView
import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Wraps `SourceEditor` from CodeEditSourceEditor, bridging document state and
/// configuration from `AppState` and `EditorState`.
///
/// Selection flows both ways: the document holds the source of truth, `SourceEditor`
/// updates its cursor on load, and user movements write back via `onChange`.
public struct CodeEditorView: View {
    @Bindable var document: CodeEditorCore.Document
    let theme: Theme
    let editorState: EditorState
    let appState: AppState

    @State private var sourceEditorState = SourceEditorState()
    @State private var textCoordinator: DocumentTextCoordinator
    @State private var lspCoordinator: LSPTextViewCoordinator

    public init(
        document: CodeEditorCore.Document,
        theme: Theme,
        editorState: EditorState,
        appState: AppState
    ) {
        self.document = document
        self.theme = theme
        self.editorState = editorState
        self.appState = appState
        _textCoordinator = State(initialValue: DocumentTextCoordinator(document: document))
        _lspCoordinator = State(
            initialValue: LSPTextViewCoordinator(
                document: document, theme: theme, appState: appState
            )
        )
    }

    public var body: some View {
        SourceEditor(
            textBinding,
            language: document.language.codeLanguage,
            configuration: configuration,
            state: $sourceEditorState,
            undoManager: undoManager,
            coordinators: [textCoordinator, lspCoordinator],
            completionDelegate: lspCoordinator,
            jumpToDefinitionDelegate: lspCoordinator
        )
        .background(theme.background.color)
        .onChange(of: sourceEditorState.cursorPositions) { _, positions in
            syncSelection(with: positions)
        }
        .onChange(of: document.id) { _, _ in
            // SourceEditor does not diff text on update — only language, configuration
            // and highlight providers. Without this, switching tabs keeps the previous
            // document on screen.
            textCoordinator.updateDocument(document)
            textCoordinator.reload(text: document.content)
            Task { await lspCoordinator.switchTo(document: document) }
            editorState.syncSelection(of: document)
        }
        .task {
            textCoordinator.updateDocument(document)
            editorState.syncSelection(of: document)
            await lspCoordinator.switchTo(document: document)
        }
        // The panel reports its own visibility; that is the authoritative signal,
        // so this writes back and the forward sync below becomes a no-op.
        .onChange(of: sourceEditorState.findPanelVisible) { _, visible in
            if let visible {
                editorState.isFindVisible = visible
            }
        }
        // Opening from the ⌘F command: state → panel. The upstream coordinator
        // calls showFindPanel() when state disagrees with the panel.
        .onChange(of: editorState.isFindVisible) { _, visible in
            sourceEditorState.findPanelVisible = visible
        }
    }

    // MARK: - Configuration

    private var configuration: SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: theme.editorTheme,
                useThemeBackground: true,
                font: editorState.font,
                lineHeightMultiple: editorState.lineHeight,
                wrapLines: editorState.wrapLines,
                useSystemCursor: true,
                tabWidth: editorState.tabWidth,
                bracketPairEmphasis: .underline(color: theme.secondaryText.nsColor)
            ),
            behavior: .init(
                isEditable: !document.isReadOnly,
                indentOption: editorState.indentOption,
                reformatAtColumn: editorState.reformatAtColumn
            ),
            peripherals: .init(
                showGutter: true,
                showMinimap: editorState.showMinimap,
                showReformattingGuide: false,
                showFoldingRibbon: editorState.showFoldingRibbon,
                invisibleCharactersConfiguration: invisibles,
                warningCharacters: Self.warningCharacters,
                codeSuggestionTriggerCharacters: [".", ":", "/", "@", "$", "_"]
            )
        )
    }

    /// Invisibles render spaces as dots and tabs as arrows when enabled. Line
    /// endings stay hidden: every line would carry a marker and the noise outweighs
    /// the signal outside of line-ending forensics.
    private var invisibles: InvisibleCharactersConfiguration {
        InvisibleCharactersConfiguration(
            showSpaces: editorState.showInvisibles,
            showTabs: editorState.showInvisibles,
            showLineEndings: false
        )
    }

    /// Characters that look like what the user meant to type but are not: smart
    /// quotes pasted into source, and the invisible spaces. Drawn as warnings.
    ///
    /// Straight quotes are deliberately **not** here. They are the correct character
    /// in code, and flagging them paints every string literal in every language with
    /// a warning background.
    private static let warningCharacters: Set<UInt16> = [
        "“", "”", "‘", "’", "\u{00A0}", "\u{200B}",
    ].reduce(into: Set<UInt16>()) { set, character in
        for unit in character.utf16 {
            set.insert(unit)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { document.content },
            set: { document.setContent($0) }
        )
    }

    private var undoManager: CEUndoManager? {
        document.undoManager as? CEUndoManager
    }

    // MARK: - Selection sync

    /// Translate the editor's 1-indexed cursor positions back into document offsets.
    private func syncSelection(with positions: [CursorPosition]?) {
        guard let position = positions?.first else { return }
        guard let offset = offset(for: position) else { return }

        document.setSelection(location: offset)
        editorState.syncSelection(of: document)
    }

    private func offset(for position: CursorPosition) -> Int? {
        if position.range != .notFound {
            return position.range.location
        }
        let lineIndex = position.start.line - 1
        guard lineIndex >= 0, lineIndex < document.lines.count else { return nil }
        return document.offset(forLine: lineIndex, column: position.start.column - 1)
    }
}
