import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditorCore
import CodeEditorThemes
import SwiftUI

extension Language {
    /// The tree-sitter language used for highlighting, resolved from the file extension.
    var codeLanguage: CodeLanguage {
        guard let ext = fileExtensions.first else { return .default }
        return CodeLanguage.detectLanguageFrom(url: URL(fileURLWithPath: "file.\(ext)"))
    }
}

extension CodeLanguage {
    /// Map back to our own language model, used when the server reports a language id.
    var editorLanguage: Language {
        Language.allLanguages.first { $0.identifier == id.rawValue } ?? .unknown
    }
}

extension Language {
    /// Every language the editor can describe, ordered for menus.
    static let allLanguages: [Language] = CodeEditorCore.Language.allLanguages
}

extension Theme {
    /// Bridge to the source editor's theme type.
    var editorTheme: EditorTheme {
        EditorTheme(
            text: .init(color: text.nsColor),
            insertionPoint: cursor.nsColor,
            invisibles: .init(color: secondaryText.nsColor),
            background: background.nsColor,
            lineHighlight: currentLine.nsColor,
            selection: selection.nsColor,
            keywords: .init(color: keyword.nsColor),
            commands: .init(color: function.nsColor),
            types: .init(color: type.nsColor, bold: true),
            attributes: .init(color: property.nsColor, italic: true),
            variables: .init(color: variable.nsColor),
            values: .init(color: number.nsColor),
            numbers: .init(color: number.nsColor),
            strings: .init(color: string.nsColor),
            characters: .init(color: text.nsColor),
            comments: .init(color: comment.nsColor, italic: true)
        )
    }
}
