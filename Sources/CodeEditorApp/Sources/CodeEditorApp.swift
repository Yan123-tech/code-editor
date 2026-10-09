import SwiftUI
import CodeEditorCore
import CodeEditorThemes
import CodeEditorUI

@main
struct CodeEditorApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Code Editor", id: "main-window") {
            MainWindowView(appState: appState)
                .frame(minWidth: 720, minHeight: 480)
                .onReceive(
                    NotificationCenter.default.publisher(for: .codeEditorOpenFolder)
                ) { _ in
                    appState.openFolder()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .codeEditorOpenFiles)
                ) { notification in
                    guard let urls = notification.object as? [URL] else { return }
                    for url in urls {
                        appState.openFile(url)
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands { commands }
    }

    @CommandsBuilder
    private var commands: some Commands {
        // MARK: File
        CommandGroup(replacing: .newItem) {
            Button("New File") {
                appState.newFile()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Folder…") {
                appState.openFolder()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open File…") {
                presentOpenFilePanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                appState.saveActiveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.documentManager.activeDocument == nil)

            Button("Save All") {
                appState.saveAllDocuments()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!appState.documentManager.hasModifiedDocuments)

            Button("Close Tab") {
                if let document = appState.documentManager.activeDocument {
                    appState.close(document)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(appState.documentManager.activeDocument == nil)
        }

        // MARK: View
        CommandGroup(after: .sidebar) {
            Button(appState.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                appState.toggleSidebar()
            }
            .keyboardShortcut("b", modifiers: .command)

            Toggle("Status Bar", isOn: Binding(
                get: { appState.isStatusBarVisible },
                set: { appState.isStatusBarVisible = $0 }
            ))
        }

        CommandGroup(after: .toolbar) {
            Button(appState.isTerminalVisible ? "Hide Terminal" : "Show Terminal") {
                appState.toggleTerminal()
            }
            .keyboardShortcut("`", modifiers: .control)
        }

        // MARK: Format
        CommandGroup(replacing: .textFormatting) {
            Toggle("Word Wrap", isOn: Binding(
                get: { appState.editorState.wrapLines },
                set: { appState.editorState.setWrapLines($0) }
            ))

            Menu("Tab Width") {
                ForEach([2, 4, 8], id: \.self) { width in
                    Button("\(width) Spaces") {
                        appState.editorState.setTabWidth(width)
                    }
                }
            }

            Menu("Font Size") {
                ForEach([11, 12, 13, 14, 16, 18], id: \.self) { size in
                    Button("\(size)") {
                        appState.editorState.setFontSize(Double(size))
                    }
                }
            }
        }

        // MARK: Theme
        CommandMenu("Theme") {
            ForEach(Theme.all, id: \.name) { theme in
                Button(theme.name) {
                    appState.themeManager.setTheme(theme)
                }
            }
            Divider()
            Button("Toggle Dark / Light") {
                appState.themeManager.toggleDarkLight()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private func presentOpenFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Open"

        guard panel.runModal() == .OK else { return }
        NotificationCenter.default.post(
            name: .codeEditorOpenFiles,
            object: panel.urls
        )
    }
}