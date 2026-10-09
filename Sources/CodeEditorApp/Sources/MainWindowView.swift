import SwiftUI
import CodeEditorCore
import CodeEditorUI

/// The app window: sidebar, tab bar, editor, terminal, status bar.
struct MainWindowView: View {
    @Bindable var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            FileExplorerView(
                fileSystemManager: appState.fileSystemManager,
                theme: appState.theme,
                onOpenFile: openFile
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
        } detail: {
            VStack(spacing: 0) {
                TabBar(documents: appState.documentManager.documents, appState: appState)

                editorArea

                if appState.isStatusBarVisible {
                    StatusBar(appState: appState)
                }

                if appState.isTerminalVisible {
                    Divider().overlay(appState.theme.separator.color)
                    TerminalView(terminal: appState.terminal, theme: appState.theme)
                        .frame(height: 220)
                }
            }
            .background(appState.theme.background.color)
        }
        .background(appState.theme.background.color)
        .tint(appState.theme.keyword.color)
        .preferredColorScheme(appState.themeManager.isDark ? .dark : .light)
        .alert("Code Editor", isPresented: errorBinding) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var editorArea: some View {
        if let document = appState.documentManager.activeDocument {
            CodeEditorView(
                document: document,
                theme: appState.theme,
                editorState: appState.editorState
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WelcomeView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.isSidebarVisible ? .all : .detailOnly },
            set: { appState.isSidebarVisible = ($0 != .detailOnly) }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }

    private func openFile(_ url: URL) {
        appState.openFile(url)
    }
}

// MARK: - Tab bar

private struct TabBar: View {
    let documents: [CodeEditorCore.Document]
    let appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(documents) { document in
                        tab(for: document)
                    }
                }
            }
            .scrollIndicators(.never)

            Button {
                appState.newFile()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .help("New File (⌘N)")
        }
        .frame(height: 28)
        .background(appState.theme.statusBarBackground.color)
    }

    private func tab(for document: CodeEditorCore.Document) -> some View {
        let isActive = document === appState.documentManager.activeDocument

        return HStack(spacing: 6) {
            Button {
                appState.documentManager.activate(document)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: document.isUntitled ? "doc" : "doc.text")
                        .font(.system(size: 10))
                    Text(document.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .foregroundColor(isActive ? appState.theme.text.color : appState.theme.secondaryText.color)
            }
            .buttonStyle(.plain)

            Button {
                appState.close(document)
            } label: {
                Image(systemName: document.isModified ? "circle.fill" : "xmark")
                    .font(.system(size: document.isModified ? 6 : 9))
                    .foregroundColor(appState.theme.secondaryText.color)
            }
            .buttonStyle(.plain)
            .help(document.isModified ? "Unsaved changes" : "Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? appState.theme.background.color : .clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? appState.theme.keyword.color : .clear)
                .frame(height: 1)
        }
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if let document = appState.documentManager.activeDocument {
                Text("Ln \(appState.editorState.caretLine + 1), Col \(appState.editorState.caretColumn + 1)")
                Text("\(document.characterCount) chars")
                Text("\(document.lineCount) lines")
                if !appState.editorState.selectedLines.isEmpty {
                    Text("\(appState.editorState.selectedLines.count) lines selected")
                }

                Spacer(minLength: 0)

                Text(document.language.displayName)

                if document.lineEnding != .lf {
                    Text(document.lineEnding == .crlf ? "CRLF" : "CR")
                }
            } else {
                Text("No document open")
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(appState.theme.secondaryText.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(height: 20)
        .background(appState.theme.statusBarBackground.color)
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(appState.theme.secondaryText.color)

            Text("No Document Open")
                .font(.title3)
                .foregroundColor(appState.theme.text.color)

            HStack(spacing: 8) {
                Button("Open Folder…") { appState.openFolder() }
                Button("New File") { appState.newFile() }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appState.theme.background.color)
    }
}

#Preview {
    MainWindowView(appState: AppState())
        .frame(width: 1200, height: 800)
}