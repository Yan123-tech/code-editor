import Foundation

/// Layout constants for the window chrome.
///
/// One grid. Spacing is a multiple of 4; radii grow with the surface they round.
/// Views must not introduce padding values that are not on this scale — the
/// original chrome used 2, 3, 5, 6 and 10 in seven combinations, which is most of
/// why it read as a draft.
///
/// Lives in `CodeEditorCore` because it is pure layout arithmetic, testable
/// without a window server, like everything else here.
public enum Metrics {
    /// Horizontal and vertical rhythm. All values are multiples of 4.
    public enum Space {
        /// Tight internal padding: icon-to-label, chip insets.
        public static let compact: CGFloat = 4

        /// Standard padding inside rows, buttons and bar items.
        public static let regular: CGFloat = 8

        /// Padding for headers, panel bodies and grouped content.
        public static let relaxed: CGFloat = 12

        /// Window-edge and section padding.
        public static let loose: CGFloat = 16

        /// Generous spacing for empty states and overlays.
        public static let spacious: CGFloat = 24
    }

    /// Corner radii, keyed by the kind of surface being rounded.
    /// Use `ContinuousCornerShape`-style smoothing (`.continuous`) with these.
    public enum Radius {
        /// List rows, tree rows, tab shapes.
        public static let row: CGFloat = 5

        /// Buttons, text fields, menu chips.
        public static let control: CGFloat = 6

        /// Docked panels and floating overlays.
        public static let panel: CGFloat = 8
    }

    /// Fixed chrome heights. Anything resizeable stores its size in preferences
    /// instead.
    public enum Height {
        /// The tab strip. Xcode is 32; 28 was cramped at the semantic font sizes.
        public static let tabStrip: CGFloat = 32

        /// The status bar.
        public static let statusBar: CGFloat = 22

        /// The terminal panel header row.
        public static let panelHeader: CGFloat = 24

        /// The drag handle between the editor and the terminal panel.
        public static let divider: CGFloat = 6

        /// The visual indicator inside the divider hit area.
        public static let dividerIndicator: CGFloat = 3
    }

    /// Indentation for each level of tree depth in the sidebar.
    public static let treeIndentPerLevel: CGFloat = 12

    /// The smallest interactive target the chrome offers.
    public static let minimumHitTarget: CGFloat = 24
}
