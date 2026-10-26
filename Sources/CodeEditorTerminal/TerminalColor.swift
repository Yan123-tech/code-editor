import Foundation

// MARK: - TerminalColor

/// An RGBA color representation for terminal text and background styles.
public struct TerminalColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0.0), 1.0)
        self.green = min(max(green, 0.0), 1.0)
        self.blue = min(max(blue, 0.0), 1.0)
        self.alpha = min(max(alpha, 0.0), 1.0)
    }

    // Standard 8 ANSI colors
    public static let black = TerminalColor(red: 0.1, green: 0.1, blue: 0.1)
    public static let red = TerminalColor(red: 0.88, green: 0.25, blue: 0.25)
    public static let green = TerminalColor(red: 0.22, green: 0.80, blue: 0.35)
    public static let yellow = TerminalColor(red: 0.88, green: 0.75, blue: 0.25)
    public static let blue = TerminalColor(red: 0.28, green: 0.55, blue: 0.95)
    public static let magenta = TerminalColor(red: 0.82, green: 0.35, blue: 0.82)
    public static let cyan = TerminalColor(red: 0.25, green: 0.78, blue: 0.88)
    public static let white = TerminalColor(red: 0.85, green: 0.85, blue: 0.85)

    // Bright 8 ANSI colors
    public static let brightBlack = TerminalColor(red: 0.45, green: 0.45, blue: 0.45)
    public static let brightRed = TerminalColor(red: 1.0, green: 0.40, blue: 0.40)
    public static let brightGreen = TerminalColor(red: 0.40, green: 0.95, blue: 0.50)
    public static let brightYellow = TerminalColor(red: 1.0, green: 0.90, blue: 0.40)
    public static let brightBlue = TerminalColor(red: 0.45, green: 0.70, blue: 1.0)
    public static let brightMagenta = TerminalColor(red: 0.95, green: 0.50, blue: 0.95)
    public static let brightCyan = TerminalColor(red: 0.40, green: 0.90, blue: 1.0)
    public static let brightWhite = TerminalColor(red: 1.0, green: 1.0, blue: 1.0)

    /// Resolve an index from the standard 256-color palette.
    public static func ansi256(_ code: Int) -> TerminalColor {
        switch code {
        case 0: return .black
        case 1: return .red
        case 2: return .green
        case 3: return .yellow
        case 4: return .blue
        case 5: return .magenta
        case 6: return .cyan
        case 7: return .white
        case 8: return .brightBlack
        case 9: return .brightRed
        case 10: return .brightGreen
        case 11: return .brightYellow
        case 12: return .brightBlue
        case 13: return .brightMagenta
        case 14: return .brightCyan
        case 15: return .brightWhite
        case 16...231:
            var c = code - 16
            let b = c % 6
            c /= 6
            let g = c % 6
            c /= 6
            let r = c % 6
            let rVal = r > 0 ? (Double(r) * 40.0 + 55.0) / 255.0 : 0.0
            let gVal = g > 0 ? (Double(g) * 40.0 + 55.0) / 255.0 : 0.0
            let bVal = b > 0 ? (Double(b) * 40.0 + 55.0) / 255.0 : 0.0
            return TerminalColor(red: rVal, green: gVal, blue: bVal)
        case 232...255:
            let gray = (Double(code - 232) * 10.0 + 8.0) / 255.0
            return TerminalColor(red: gray, green: gray, blue: gray)
        default:
            return .white
        }
    }
}

// MARK: - TerminalStyle

/// Attributes applied to a span of terminal text.
public struct TerminalStyle: Equatable, Hashable, Sendable {
    public var foregroundColor: TerminalColor?
    public var backgroundColor: TerminalColor?
    public var isBold: Bool
    public var isDim: Bool
    public var isItalic: Bool
    public var isUnderline: Bool

    public init(
        foregroundColor: TerminalColor? = nil,
        backgroundColor: TerminalColor? = nil,
        isBold: Bool = false,
        isDim: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.isBold = isBold
        self.isDim = isDim
        self.isItalic = isItalic
        self.isUnderline = isUnderline
    }

    public static let `default` = TerminalStyle()
}

// MARK: - TerminalOutputSpan

/// A continuous run of characters sharing the same formatting style.
public struct TerminalOutputSpan: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let style: TerminalStyle

    public init(id: UUID = UUID(), text: String, style: TerminalStyle = .default) {
        self.id = id
        self.text = text
        self.style = style
    }
}

// MARK: - TerminalOutputType

/// Types of terminal output, used for coloring and visual categorization.
public enum TerminalOutputType: Sendable {
    case standard
    case errorOutput
    case info
    case input
}

// MARK: - TerminalOutputLine

/// A single line of terminal output containing raw plain text and styled spans.
public struct TerminalOutputLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let type: TerminalOutputType
    public let spans: [TerminalOutputSpan]

    public init(
        id: UUID = UUID(),
        text: String,
        type: TerminalOutputType = .standard,
        spans: [TerminalOutputSpan] = []
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.spans = spans
    }
}
