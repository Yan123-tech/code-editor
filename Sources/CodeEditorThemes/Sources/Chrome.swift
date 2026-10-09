import SwiftUI

// MARK: - Chrome

/// Tokens for the window chrome around the code canvas: sidebar, bars, panels,
/// overlays, and the app-wide accent.
///
/// These exist so chrome colors stop being borrowed from syntax tokens. The accent
/// used to be `Theme.keyword`, which meant the tab underline, the folder icons, the
/// terminal prompt and terminal *errors* all changed meaning whenever the syntax
/// palette did. A chrome token means one thing and is tuned for chrome.
///
/// When `usesMaterials` is true, views should prefer system materials over these
/// fills — the tokens then act as fallbacks and as the source for derived states
/// such as hover washes. High Contrast sets the flag to false and uses the fills
/// directly, because translucency trades contrast for depth.
public struct Chrome: Sendable, Equatable {
    /// The one saturated color the app may use for selection, focus and links.
    public var accent: EditorColor

    /// Fallback fill for the sidebar when materials are off.
    public var sidebarBackground: EditorColor

    /// Row hover wash in lists and trees.
    public var rowHover: EditorColor

    /// Fill for the selected row, typically the accent at low alpha.
    public var rowSelected: EditorColor

    /// Fallback fill for the tab strip and status bar when materials are off.
    public var barBackground: EditorColor

    /// Fill of the active tab. Equal to the canvas so the tab merges into it.
    public var tabActiveBackground: EditorColor

    /// Hover wash for inactive tabs.
    public var tabHoverBackground: EditorColor

    /// Fill for docked panels such as the terminal.
    public var panelBackground: EditorColor

    /// Fill for floating chrome: find bar, quick open, popovers.
    public var overlayBackground: EditorColor

    /// Hairlines and separators.
    public var border: EditorColor

    /// Whether views should prefer system materials over the fills above.
    public var usesMaterials: Bool

    public init(
        accent: EditorColor,
        sidebarBackground: EditorColor,
        rowHover: EditorColor,
        rowSelected: EditorColor,
        barBackground: EditorColor,
        tabActiveBackground: EditorColor,
        tabHoverBackground: EditorColor,
        panelBackground: EditorColor,
        overlayBackground: EditorColor,
        border: EditorColor,
        usesMaterials: Bool = true
    ) {
        self.accent = accent
        self.sidebarBackground = sidebarBackground
        self.rowHover = rowHover
        self.rowSelected = rowSelected
        self.barBackground = barBackground
        self.tabActiveBackground = tabActiveBackground
        self.tabHoverBackground = tabHoverBackground
        self.panelBackground = panelBackground
        self.overlayBackground = overlayBackground
        self.border = border
        self.usesMaterials = usesMaterials
    }
}

// MARK: - Semantic

/// Status colors that mean the same thing everywhere they appear: connection state,
/// terminal errors, and later diagnostics.
public struct Semantic: Sendable, Equatable {
    public var danger: EditorColor
    public var success: EditorColor
    public var warning: EditorColor

    public init(danger: EditorColor, success: EditorColor, warning: EditorColor) {
        self.danger = danger
        self.success = success
        self.warning = warning
    }
}
