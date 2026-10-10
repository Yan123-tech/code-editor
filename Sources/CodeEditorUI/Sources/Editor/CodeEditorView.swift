import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// The editing surface: a tree-sitter highlighted source editor with its own line
/// number gutter, bracket emphasis and undo stack.
public struct CodeEditorView: View {
    @Bindable var document: CodeEditorCore.Document
    let theme: Theme
    let editorState: EditorState

    @State private var sourceEditorState = SourceEditorState()
    @State private var textCoordinator = DocumentTextCoordinator()

    public init(document: CodeEditorCore.Document, theme: Theme, editorState: EditorState) {
        self.document = document
        self.theme = theme
        self.editorState = editorState
    }

    public var body: some View {
        SourceEditor(
            textBinding,
            language: document.language.codeLanguage,
            configuration: configuration,
            state: $sourceEditorState,
            undoManager: undoManager,
            coordinators: [textCoordinator]
        )
        .background(theme.background.color)
        .onChange(of: sourceEditorState.cursorPositions) { _, positions in
            syncSelection(with: positions)
        }
        .onChange(of: document.id) { _, _ in
            // SourceEditor does not diff text on update — only language, configuration
            // and highlight providers. Without this, switching tabs keeps the previous
            // document on screen.
            textCoordinator.reload(text: document.content)
            editorState.syncSelection(of: document)
        }
        .task {
            editorState.syncSelection(of: document)
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
                warningCharacters: Self.warningCharacters
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

    /// Two-way binding between the editor and the document's content.
    private var textBinding: Binding<String> {
        Binding(
            get: { document.content },
            set: { document.setContent($0) }
        )
    }

    private var undoManager: CEUndoManager? {
        document.undoManager as? CEUndoManager
    }

    // MARK: - Caret tracking

    /// Translate the editor's 1-indexed cursor positions back into document offsets.
    private func syncSelection(with positions: [CursorPosition]?) {
        guard let position = positions?.first else { return }
        guard let offset = offset(for: position) else { return }

        document.setSelection(location: offset)
        editorState.syncSelection(of: document)
    }

    private func offset(for position: CursorPosition) -> Int? {
        let lineIndex = position.start.line - 1
        guard lineIndex >= 0, lineIndex < document.lines.count else { return nil }

        var offset = 0
        for index in 0..<lineIndex {
            offset += document.lines[index].utf8.count + document.lineEnding.character.utf8.count
        }
        return offset + document.lines[lineIndex].utf8.prefix(max(0, position.start.column - 1)).count
    }
}
