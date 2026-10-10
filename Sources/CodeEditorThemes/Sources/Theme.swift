import SwiftUI

// MARK: - Theme

/// The palette for one appearance: the code canvas, the syntax tokens, the chrome
/// around them, and the system appearance the window should force.
///
/// The canvas and syntax fields feed `EditorTheme` through the bridge in
/// `CodeEditorUI`; the `chrome` and `semantic` groups feed the window chrome.
public struct Theme: Sendable, Equatable {
    public var background: EditorColor
    public var text: EditorColor
    public var secondaryText: EditorColor
    public var lineNumber: EditorColor
    public var currentLine: EditorColor
    public var selection: EditorColor
    public var cursor: EditorColor

    // Syntax highlighting
    public var keyword: EditorColor
    public var string: EditorColor
    public var comment: EditorColor
    public var number: EditorColor
    public var type: EditorColor
    public var variable: EditorColor
    public var function: EditorColor
    public var property: EditorColor

    /// The system appearance this palette should force on the window, so materials
    /// and system controls agree with the canvas. Declared per palette rather than
    /// derived — see `ThemeManager.isDark` for why deriving does not work.
    public var colorScheme: ColorScheme

    /// Window chrome tokens. See `Chrome`.
    public var chrome: Chrome

    /// Status colors. See `Semantic`.
    public var semantic: Semantic

    public init(
        background: EditorColor,
        text: EditorColor,
        secondaryText: EditorColor,
        lineNumber: EditorColor,
        currentLine: EditorColor,
        selection: EditorColor,
        cursor: EditorColor,
        keyword: EditorColor,
        string: EditorColor,
        comment: EditorColor,
        number: EditorColor,
        type: EditorColor,
        variable: EditorColor,
        function: EditorColor,
        property: EditorColor,
        colorScheme: ColorScheme = .dark,
        chrome: Chrome,
        semantic: Semantic
    ) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.lineNumber = lineNumber
        self.currentLine = currentLine
        self.selection = selection
        self.cursor = cursor
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.type = type
        self.variable = variable
        self.function = function
        self.property = property
        self.colorScheme = colorScheme
        self.chrome = chrome
        self.semantic = semantic
    }

    /// One Dark Plus-ish palette.
    public static let dark = Theme(
        background: EditorColor(hex: "#1e1e1e"),
        text: EditorColor(hex: "#d4d4d4"),
        secondaryText: EditorColor(hex: "#858585"),
        lineNumber: EditorColor(hex: "#6a6a6a"),
        currentLine: EditorColor(hex: "#2a2a2a"),
        selection: EditorColor(hex: "#264f78"),
        cursor: EditorColor(hex: "#aeafad"),
        keyword: EditorColor(hex: "#569cd6"),
        string: EditorColor(hex: "#ce9178"),
        comment: EditorColor(hex: "#6a9955"),
        number: EditorColor(hex: "#b5cea8"),
        type: EditorColor(hex: "#4ec9b0"),
        variable: EditorColor(hex: "#9cdcfe"),
        function: EditorColor(hex: "#dcdcaa"),
        property: EditorColor(hex: "#d4d4d4"),
        colorScheme: .dark,
        chrome: Chrome(
            accent: EditorColor(hex: "#4c8dff"),
            sidebarBackground: EditorColor(hex: "#181818"),
            rowHover: EditorColor(hex: "#262626"),
            rowSelected: EditorColor(hex: "#4c8dff2e"),
            barBackground: EditorColor(hex: "#252526"),
            tabActiveBackground: EditorColor(hex: "#1e1e1e"),
            tabHoverBackground: EditorColor(hex: "#2a2a2b"),
            panelBackground: EditorColor(hex: "#1b1b1b"),
            overlayBackground: EditorColor(hex: "#242424"),
            border: EditorColor(hex: "#3c3c3c"),
            usesMaterials: true
        ),
        semantic: Semantic(
            danger: EditorColor(hex: "#ff6b6b"),
            success: EditorColor(hex: "#5bd675"),
            warning: EditorColor(hex: "#e3b341")
        )
    )

    /// A light counterpart to `dark`.
    public static let light = Theme(
        background: EditorColor(hex: "#ffffff"),
        text: EditorColor(hex: "#1f1f1f"),
        secondaryText: EditorColor(hex: "#6e6e6e"),
        lineNumber: EditorColor(hex: "#a0a0a0"),
        currentLine: EditorColor(hex: "#f3f3f3"),
        selection: EditorColor(hex: "#add6ff"),
        cursor: EditorColor(hex: "#000000"),
        keyword: EditorColor(hex: "#0000ff"),
        string: EditorColor(hex: "#a31515"),
        comment: EditorColor(hex: "#008000"),
        number: EditorColor(hex: "#098658"),
        type: EditorColor(hex: "#267f99"),
        variable: EditorColor(hex: "#001080"),
        function: EditorColor(hex: "#795e26"),
        property: EditorColor(hex: "#1f1f1f"),
        colorScheme: .light,
        chrome: Chrome(
            accent: EditorColor(hex: "#0a66ff"),
            sidebarBackground: EditorColor(hex: "#f6f6f6"),
            rowHover: EditorColor(hex: "#e8e8e8"),
            rowSelected: EditorColor(hex: "#0a66ff24"),
            barBackground: EditorColor(hex: "#f3f3f3"),
            tabActiveBackground: EditorColor(hex: "#ffffff"),
            tabHoverBackground: EditorColor(hex: "#eaeaea"),
            panelBackground: EditorColor(hex: "#fafafa"),
            overlayBackground: EditorColor(hex: "#ffffff"),
            border: EditorColor(hex: "#d4d4d4"),
            usesMaterials: true
        ),
        semantic: Semantic(
            danger: EditorColor(hex: "#d7263d"),
            success: EditorColor(hex: "#1e8e3e"),
            warning: EditorColor(hex: "#b26a00")
        )
    )

    /// Maximum contrast, for accessibility. Materials are off: translucency
    /// spends contrast, which is the one thing this palette cannot spare.
    public static let highContrast = Theme(
        background: EditorColor(hex: "#000000"),
        text: EditorColor(hex: "#ffffff"),
        secondaryText: EditorColor(hex: "#cccccc"),
        lineNumber: EditorColor(hex: "#aaaaaa"),
        currentLine: EditorColor(hex: "#1a1a1a"),
        selection: EditorColor(hex: "#0066cc"),
        cursor: EditorColor(hex: "#ffffff"),
        keyword: EditorColor(hex: "#ffcc66"),
        string: EditorColor(hex: "#99cc99"),
        comment: EditorColor(hex: "#99cc99"),
        number: EditorColor(hex: "#ffff99"),
        type: EditorColor(hex: "#66ccff"),
        variable: EditorColor(hex: "#ffffff"),
        function: EditorColor(hex: "#ff99cc"),
        property: EditorColor(hex: "#ffffff"),
        colorScheme: .dark,
        chrome: Chrome(
            accent: EditorColor(hex: "#ffcc66"),
            sidebarBackground: EditorColor(hex: "#000000"),
            rowHover: EditorColor(hex: "#1a1a1a"),
            rowSelected: EditorColor(hex: "#333333"),
            barBackground: EditorColor(hex: "#000000"),
            tabActiveBackground: EditorColor(hex: "#000000"),
            tabHoverBackground: EditorColor(hex: "#222222"),
            panelBackground: EditorColor(hex: "#000000"),
            overlayBackground: EditorColor(hex: "#0a0a0a"),
            border: EditorColor(hex: "#ffffff"),
            usesMaterials: false
        ),
        semantic: Semantic(
            danger: EditorColor(hex: "#ff6b6b"),
            success: EditorColor(hex: "#5bd675"),
            warning: EditorColor(hex: "#ffff00")
        )
    )

    public static let all: [Theme] = [.dark, .light, .highContrast]
}

extension Theme {
    /// Stable identifier used for persistence.
    public var name: String {
        if self == .dark { return "Dark" }
        if self == .light { return "Light" }
        if self == .highContrast { return "High Contrast" }
        return "Custom"
    }
}
