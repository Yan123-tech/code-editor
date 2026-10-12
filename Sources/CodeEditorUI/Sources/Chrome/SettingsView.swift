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
    @State private var modelSearchQuery = ""

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

                // MARK: Autocompletion
                Section("Autocompletion") {
                    Picker("Engine", selection: completionModeBinding) {
                        Text("Language Server (LSP)").tag(EditorState.CompletionMode.lsp)
                        Text("AI (Copilot-style)").tag(EditorState.CompletionMode.ai)
                    }
                    .pickerStyle(.segmented)

                    if appState.editorState.completionMode == .ai {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("OpenAI-Compatible API")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Base URL (e.g. https://api.openai.com/v1)", text: aiBaseURLBinding)
                                .textFieldStyle(.roundedBorder)

                            SecureField("API Key (leave blank for local models)", text: aiApiKeyBinding)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 12) {
                                Button {
                                    Task { await appState.fetchAIModels() }
                                } label: {
                                    HStack(spacing: 4) {
                                        if appState.editorState.aiIsFetchingModels {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                        }
                                        Text("Fetch Models")
                                    }
                                }
                                .disabled(appState.editorState.aiIsFetchingModels)

                                if let error = appState.editorState.aiFetchError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(appState.theme.semantic.danger.color)
                                        .lineLimit(2)
                                } else if !appState.editorState.aiAvailableModels.isEmpty {
                                    Text("\(appState.editorState.aiAvailableModels.count) models available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !appState.editorState.aiAvailableModels.isEmpty {
                                Divider()

                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search model...", text: $modelSearchQuery)
                                        .textFieldStyle(.plain)
                                }
                                .padding(4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)

                                Menu {
                                    ForEach(filteredModels, id: \.self) { model in
                                        Button {
                                            appState.editorState.setAIModel(model)
                                        } label: {
                                            HStack {
                                                Text(model)
                                                if appState.editorState.aiModel == model {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label(
                                        appState.editorState.aiModel.isEmpty
                                            ? "Select Model" : "Model: \(appState.editorState.aiModel)",
                                        systemImage: "cpu"
                                    )
                                }
                            } else {
                                TextField("Model Name (e.g. gpt-4o-mini)", text: aiModelBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
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

    private var completionModeBinding: Binding<EditorState.CompletionMode> {
        Binding(
            get: { appState.editorState.completionMode },
            set: { appState.editorState.setCompletionMode($0) }
        )
    }

    private var aiBaseURLBinding: Binding<String> {
        Binding(
            get: { appState.editorState.aiBaseURL },
            set: { appState.editorState.setAIBaseURL($0) }
        )
    }

    private var aiApiKeyBinding: Binding<String> {
        Binding(
            get: { appState.editorState.aiApiKey },
            set: { appState.editorState.setAIApiKey($0) }
        )
    }

    private var aiModelBinding: Binding<String> {
        Binding(
            get: { appState.editorState.aiModel },
            set: { appState.editorState.setAIModel($0) }
        )
    }

    private var filteredModels: [String] {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return appState.editorState.aiAvailableModels
        }
        return appState.editorState.aiAvailableModels.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

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
