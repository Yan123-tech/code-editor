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
    public var lineHeight: Double = 1.35
    public var reformatAtColumn: Int = 80
    public var wrapLines: Bool = false
    public var showMinimap = false
    public var showFoldingRibbon = true
    public var showInvisibles = false

    // Transient state for the active document
    public private(set) var selectedLines: Set<Int> = []
    public private(set) var caretLine = 0
    public private(set) var caretColumn = 0
    public private(set) var caretOffset = 0

    /// Whether the editor's find panel is being asked to show. Synced both ways by
    /// `CodeEditorView`: setting true opens the panel, dismissing the panel clears it.
    public var isFindVisible = false

    private static let fontSizeKey = "CodeEditor.fontSize"
    private static let tabWidthKey = "CodeEditor.tabWidth"
    private static let wrapKey = "CodeEditor.wrapLines"
    private static let minimapKey = "CodeEditor.showMinimap"
    private static let foldingKey = "CodeEditor.showFoldingRibbon"
    private static let invisiblesKey = "CodeEditor.showInvisibles"

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
        if defaults.object(forKey: Self.minimapKey) != nil {
            showMinimap = defaults.bool(forKey: Self.minimapKey)
        }
        if defaults.object(forKey: Self.foldingKey) != nil {
            showFoldingRibbon = defaults.bool(forKey: Self.foldingKey)
        }
        if defaults.object(forKey: Self.invisiblesKey) != nil {
            showInvisibles = defaults.bool(forKey: Self.invisiblesKey)
        }
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

    public func setShowMinimap(_ show: Bool, defaults: UserDefaults = .standard) {
        showMinimap = show
        defaults.set(show, forKey: Self.minimapKey)
    }

    public func setShowFoldingRibbon(_ show: Bool, defaults: UserDefaults = .standard) {
        showFoldingRibbon = show
        defaults.set(show, forKey: Self.foldingKey)
    }

    public func setShowInvisibles(_ show: Bool, defaults: UserDefaults = .standard) {
        showInvisibles = show
        defaults.set(show, forKey: Self.invisiblesKey)
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

        selectedLines = document.selectedLines(for: selection)
    }

    public func setCaret(line: Int, column: Int) {
        caretLine = line
        caretColumn = column
    }
}
