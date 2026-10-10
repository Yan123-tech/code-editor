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

    /// The same color at a different opacity, for selected-row fills and hover washes.
    public func withAlpha(_ alpha: Double) -> EditorColor {
        EditorColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
