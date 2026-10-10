import SwiftUI

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
