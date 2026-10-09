import SwiftUI

// MARK: - Typography

/// The chrome type ramp. Semantic styles only, so chrome text scales with the
/// user's system text size the way it does in Xcode.
///
/// The code canvas is deliberately absent: the editor font is a fixed-size SF Mono
/// owned by `EditorState` and persisted as a preference, because code reflowing
/// under Dynamic Type is disruptive mid-edit.
///
/// Rule: chrome views use these roles. `.system(size:)` is banned outside the
/// canvas — the original chrome hardcoded 11pt and 12pt in thirteen places, which
/// neither scaled nor stayed consistent.
public enum Typography {
    /// Sidebar tree rows and file names. `.body`, 13pt — the Xcode navigator size.
    public static let sidebarRow: Font = .body

    /// Tab strip labels.
    public static let tabLabel: Font = .subheadline

    /// Sidebar section headers such as the project name. Never all-caps.
    public static let sectionHeader: Font = .caption.weight(.semibold)

    /// Status bar readouts.
    public static let statusBar: Font = .caption

    /// Panel headers, such as the terminal's title row.
    public static let panelHeader: Font = .caption.weight(.semibold)

    /// The empty-state headline.
    public static let emptyTitle: Font = .title2.weight(.semibold)

    /// The empty-state supporting line.
    public static let emptyBody: Font = .callout

    /// Keyboard-hint chips in overlays.
    public static let hint: Font = .caption2.monospaced()
}
