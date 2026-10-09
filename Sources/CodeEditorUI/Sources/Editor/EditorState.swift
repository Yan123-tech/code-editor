import CodeEditSourceEditor
import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Editor preferences and transient view state for the active document.
@MainActor
@Observable
public final class EditorState {
    // Preferences
    public var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    public var tabWidth: Int = 4
    public var indentOption: IndentOption = .spaces(count: 4)
    public var lineHeight: Double = 1.2
    public var reformatAtColumn: Int = 80
    public var wrapLines: Bool = false

    // Transient state for the active document
    public private(set) var selectedLines: Set<Int> = []
    public private(set) var caretLine = 0
    public private(set) var caretColumn = 0
    public private(set) var caretOffset = 0

    private static let fontSizeKey = "CodeEditor.fontSize"
    private static let tabWidthKey = "CodeEditor.tabWidth"
    private static let wrapKey = "CodeEditor.wrapLines"

    public init() {}

    // MARK: - Persistence

    public func loadPersistedSettings(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: Self.fontSizeKey) != nil {
            let size = defaults.double(forKey: Self.fontSizeKey)
            font = .monospacedSystemFont(ofSize: max(9, min(48, size)), weight: .regular)
        }
        if defaults.object(forKey: Self.tabWidthKey) != nil {
            tabWidth = max(1, min(8, defaults.integer(forKey: Self.tabWidthKey)))
        }
        wrapLines = defaults.bool(forKey: Self.wrapKey)
        indentOption = .spaces(count: tabWidth)
    }

    public func setFontSize(_ size: Double, defaults: UserDefaults = .standard) {
        font = .monospacedSystemFont(ofSize: max(9, min(48, size)), weight: .regular)
        defaults.set(size, forKey: Self.fontSizeKey)
    }

    public func setTabWidth(_ width: Int, defaults: UserDefaults = .standard) {
        tabWidth = max(1, min(8, width))
        indentOption = .spaces(count: tabWidth)
        defaults.set(tabWidth, forKey: Self.tabWidthKey)
    }

    public func setWrapLines(_ wrap: Bool, defaults: UserDefaults = .standard) {
        wrapLines = wrap
        defaults.set(wrap, forKey: Self.wrapKey)
    }

    // MARK: - Caret tracking

    /// Recompute the status bar position from a document selection.
    public func syncSelection(of document: CodeEditorCore.Document?) {
        guard let document else {
            selectedLines = []
            caretLine = 0
            caretColumn = 0
            caretOffset = 0
            return
        }

        let selection = document.selection
        let start = document.lineAndColumn(for: selection.start)
        let end = document.lineAndColumn(for: selection.end)

        if let start {
            caretLine = start.line
            caretColumn = start.column
            caretOffset = selection.start
        }

        if let start, let end {
            selectedLines = Set(start.line...end.line)
        } else {
            selectedLines = []
        }
    }

    public func setCaret(line: Int, column: Int) {
        caretLine = line
        caretColumn = column
    }
}
