import SwiftUI

// MARK: - EditorColor

/// An sRGB color that can be declared from hex in code and handed to AppKit or SwiftUI.
public struct EditorColor: Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parse `#rrggbb` or `#rrggbbaa`. Falls back to black on malformed input.
    public init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }

        var number: UInt64 = 0
        guard value.count == 6 || value.count == 8, Scanner(string: value).scanHexInt64(&number) else {
            self.init(red: 0, green: 0, blue: 0)
            return
        }

        let hasAlpha = value.count == 8
        self.init(
            red: Double((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255,
            green: Double((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255,
            blue: Double((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255,
            alpha: hasAlpha ? Double(number & 0xFF) / 255 : 1
        )
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

// MARK: - Theme

/// Colors used by the editor chrome and for syntax highlighting.
public struct Theme: Sendable, Equatable {
    public var background: EditorColor
    public var text: EditorColor
    public var secondaryText: EditorColor
    public var lineNumber: EditorColor
    public var currentLine: EditorColor
    public var selection: EditorColor
    public var cursor: EditorColor
    public var statusBarBackground: EditorColor
    public var separator: EditorColor

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

    public init(
        background: EditorColor,
        text: EditorColor,
        secondaryText: EditorColor,
        lineNumber: EditorColor,
        currentLine: EditorColor,
        selection: EditorColor,
        cursor: EditorColor,
        statusBarBackground: EditorColor,
        separator: EditorColor,
        keyword: EditorColor,
        string: EditorColor,
        comment: EditorColor,
        number: EditorColor,
        type: EditorColor,
        variable: EditorColor,
        function: EditorColor,
        property: EditorColor,
        colorScheme: ColorScheme = .dark
    ) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.lineNumber = lineNumber
        self.currentLine = currentLine
        self.selection = selection
        self.cursor = cursor
        self.statusBarBackground = statusBarBackground
        self.separator = separator
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.type = type
        self.variable = variable
        self.function = function
        self.property = property
        self.colorScheme = colorScheme
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
        statusBarBackground: EditorColor(hex: "#252526"),
        separator: EditorColor(hex: "#3c3c3c"),
        keyword: EditorColor(hex: "#569cd6"),
        string: EditorColor(hex: "#ce9178"),
        comment: EditorColor(hex: "#6a9955"),
        number: EditorColor(hex: "#b5cea8"),
        type: EditorColor(hex: "#4ec9b0"),
        variable: EditorColor(hex: "#9cdcfe"),
        function: EditorColor(hex: "#dcdcaa"),
        property: EditorColor(hex: "#d4d4d4"),
        colorScheme: .dark
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
        statusBarBackground: EditorColor(hex: "#f3f3f3"),
        separator: EditorColor(hex: "#d4d4d4"),
        keyword: EditorColor(hex: "#0000ff"),
        string: EditorColor(hex: "#a31515"),
        comment: EditorColor(hex: "#008000"),
        number: EditorColor(hex: "#098658"),
        type: EditorColor(hex: "#267f99"),
        variable: EditorColor(hex: "#001080"),
        function: EditorColor(hex: "#795e26"),
        property: EditorColor(hex: "#1f1f1f"),
        colorScheme: .light
    )

    /// Maximum contrast, for accessibility.
    public static let highContrast = Theme(
        background: EditorColor(hex: "#000000"),
        text: EditorColor(hex: "#ffffff"),
        secondaryText: EditorColor(hex: "#cccccc"),
        lineNumber: EditorColor(hex: "#aaaaaa"),
        currentLine: EditorColor(hex: "#1a1a1a"),
        selection: EditorColor(hex: "#0066cc"),
        cursor: EditorColor(hex: "#ffffff"),
        statusBarBackground: EditorColor(hex: "#000000"),
        separator: EditorColor(hex: "#ffffff"),
        keyword: EditorColor(hex: "#ffcc66"),
        string: EditorColor(hex: "#99cc99"),
        comment: EditorColor(hex: "#99cc99"),
        number: EditorColor(hex: "#ffff99"),
        type: EditorColor(hex: "#66ccff"),
        variable: EditorColor(hex: "#ffffff"),
        function: EditorColor(hex: "#ff99cc"),
        property: EditorColor(hex: "#ffffff"),
        colorScheme: .dark
    )

    public static let all: [Theme] = [.dark, .light, .highContrast]
}

// MARK: - ThemeManager

/// Holds the active theme and persists the choice.
@MainActor
@Observable
public final class ThemeManager {
    public private(set) var currentTheme: Theme

    private static let storageKey = "CodeEditor.selectedTheme"

    public init(theme: Theme = .dark) {
        self.currentTheme = theme
    }

    /// Restore the persisted theme, if any.
    public func loadPersistedTheme(defaults: UserDefaults = .standard) {
        guard let name = defaults.string(forKey: Self.storageKey) else { return }
        if let theme = theme(named: name) {
            currentTheme = theme
        }
    }

    public func setTheme(_ theme: Theme, defaults: UserDefaults = .standard) {
        currentTheme = theme
        defaults.set(theme.name, forKey: Self.storageKey)
    }

    public func setTheme(named name: String, defaults: UserDefaults = .standard) {
        guard let theme = theme(named: name) else { return }
        setTheme(theme, defaults: defaults)
    }

    public func toggleDarkLight(defaults: UserDefaults = .standard) {
        setTheme(currentTheme == .dark ? .light : .dark, defaults: defaults)
    }

    public func theme(named name: String) -> Theme? {
        Theme.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Whether the palette forces a dark system appearance.
    ///
    /// Reads the declared `colorScheme`. The previous implementation compared the
    /// background's red and blue channels, which returns `false` for any neutral
    /// background — `#1e1e1e` is `30 < 30` — so the Dark and High Contrast palettes
    /// rendered all system chrome in light mode. Do not derive this from colour
    /// arithmetic again.
    public var isDark: Bool {
        currentTheme.colorScheme == .dark
    }
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
