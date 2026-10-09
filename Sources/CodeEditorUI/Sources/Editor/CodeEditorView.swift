import SwiftUI
import CodeEditorCore
import CodeEditorThemes
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView

/// The editing surface: a tree-sitter highlighted source editor with its own line number
/// gutter, bracket emphasis and undo stack.
public struct CodeEditorView: View {
    @Bindable var document: CodeEditorCore.Document
    let theme: Theme
    let editorState: EditorState

    @State private var sourceEditorState = SourceEditorState()

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
            undoManager: undoManager
        )
        .background(theme.background.color)
        .onChange(of: sourceEditorState.cursorPositions) { _, positions in
            syncSelection(with: positions)
        }
        .onChange(of: document.id) { _, _ in
            editorState.syncSelection(of: document)
        }
        .task {
            editorState.syncSelection(of: document)
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
                tabWidth: editorState.tabWidth
            ),
            behavior: .init(
                isEditable: !document.isReadOnly,
                indentOption: editorState.indentOption,
                reformatAtColumn: editorState.reformatAtColumn
            )
        )
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