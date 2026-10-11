import CodeEditorThemes
import SwiftUI

/// The app-wide settings panel, presented as a sheet from the main window.
///
/// A single Form that groups every persisted editor preference — theme, font,
/// spacing and visibility toggles — so the user discovers them without hunting
/// through menu submenus. All state lives in `EditorState` and `ThemeManager`;
/// this view only presents and binds.
public struct SettingsView: View {
    @Bindable private var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: Theme
                Section("Theme") {
                    Menu {
                        ForEach(Theme.all, id: \.name) { theme in
                            Button {
                                appState.themeManager.setTheme(theme)
                            } label: {
                                HStack {
                                    Text(theme.name)
                                    if appState.theme == theme {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Toggle Dark / Light") {
                            appState.themeManager.toggleDarkLight()
                        }
                    } label: {
                        Label("Theme: \(appState.theme.name)", systemImage: "paintpalette")
                    }
                }

                // MARK: Text
                Section("Text") {
                    Menu {
                        ForEach([11, 12, 13, 14, 16, 18, 24, 36], id: \.self) { size in
                            Button("\(size)") {
                                appState.editorState.setFontSize(Double(size))
                            }
                        }
                    } label: {
                        Label("Font Size: \(Int(fontSizeValue))", systemImage: "textformat")
                    }

                    Menu {
                        ForEach([2, 4, 8], id: \.self) { width in
                            Button("\(width) Spaces") {
                                appState.editorState.setTabWidth(width)
                            }
                        }
                    } label: {
                        Label("Tab Width: \(appState.editorState.tabWidth)", systemImage: "tabletab")
                    }
                }

                // MARK: View
                Section("View") {
                    Toggle("Word Wrap", isOn: wrapBinding)
                    Toggle("Show Invisibles", isOn: invisiblesBinding)
                    Toggle("Minimap", isOn: minimapBinding)
                    Toggle("Code Folding Ribbon", isOn: foldingBinding)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        appState.isSettingsVisible = false
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private var wrapBinding: Binding<Bool> {
        Binding(
            get: { appState.editorState.wrapLines },
            set: { appState.editorState.setWrapLines($0) }
        )
    }

    private var invisiblesBinding: Binding<Bool> {
        Binding(
            get: { appState.editorState.showInvisibles },
            set: { appState.editorState.setShowInvisibles($0) }
        )
    }

    private var minimapBinding: Binding<Bool> {
        Binding(
            get: { appState.editorState.showMinimap },
            set: { appState.editorState.setShowMinimap($0) }
        )
    }

    private var foldingBinding: Binding<Bool> {
        Binding(
            get: { appState.editorState.showFoldingRibbon },
            set: { appState.editorState.setShowFoldingRibbon($0) }
        )
    }

    /// The current font size as a `Double`, so the Stepper `format:` works.
    private var fontSizeValue: Double {
        appState.editorState.font.pointSize
    }
}
