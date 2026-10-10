import CodeEditorThemes
import SwiftUI
import Testing

@Suite("ThemeManager")
@MainActor
struct ThemeManagerTests {
    @Test("Every palette declares the appearance it forces")
    func appearanceMatchesPalette() {
        let manager = ThemeManager(theme: .dark)
        #expect(manager.isDark == true)

        manager.setTheme(.light)
        #expect(manager.isDark == false)

        manager.setTheme(.highContrast)
        #expect(manager.isDark == true)
    }

    @Test("Dark and High Contrast are not misread as light")
    func neutralBackgroundsAreNotMisread() {
        // Regression: the old isDark compared background.red < background.blue,
        // which is false for any neutral background such as #1e1e1e or #000000,
        // forcing system chrome into light mode under a dark canvas.
        #expect(Theme.dark.colorScheme == .dark)
        #expect(Theme.highContrast.colorScheme == .dark)
        #expect(Theme.light.colorScheme == .light)
    }

    @Test("Persistence round-trips the theme name")
    func persistenceRoundTrips() throws {
        let suiteName = "ThemeManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(theme: .dark)
        manager.setTheme(.highContrast, defaults: defaults)

        let restored = ThemeManager(theme: .dark)
        restored.loadPersistedTheme(defaults: defaults)
        #expect(restored.currentTheme == .highContrast)
    }

    @Test("An unknown persisted name keeps the default")
    func unknownPersistedNameIsIgnored() {
        let suiteName = "ThemeManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Solarized", forKey: "CodeEditor.selectedTheme")

        let manager = ThemeManager(theme: .light)
        manager.loadPersistedTheme(defaults: defaults)
        #expect(manager.currentTheme == .light)
    }
}
