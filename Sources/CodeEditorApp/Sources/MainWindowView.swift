import CodeEditorCore
import CodeEditorThemes
import CodeEditorUI
import SwiftUI

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
                activeDocumentURL: appState.documentManager.activeDocument?.url,
                onOpenFile: { url in appState.openFile(url) },
                onCreateIn: { directory, kind in
                    appState.requestCreation(kind: kind, in: directory)
                }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
        } detail: {
            VStack(spacing: 0) {
                TabBarView(
                    documents: appState.documentManager.documents,
                    activeDocument: appState.documentManager.activeDocument,
                    theme: appState.theme,
                    onSelect: { document in appState.documentManager.activate(document) },
                    onClose: { document in appState.requestClose(document) },
                    onNew: { appState.newFile() }
                )

                editorArea

                if appState.isStatusBarVisible {
                    StatusBarView(appState: appState)
                }

                if appState.isTerminalVisible {
                    Divider().overlay(appState.theme.chrome.border.color)
                    TerminalView(terminal: appState.terminal, theme: appState.theme)
                        .frame(height: 220)
                }
            }
            .background(appState.theme.background.color)
        }
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
        .background(appState.theme.background.color)
        .tint(appState.theme.chrome.accent.color)
        .preferredColorScheme(appState.theme.colorScheme)
        .sheet(item: $appState.pendingCreation) { pending in
            NewItemSheetView(pending: pending) { name in
                appState.performCreation(named: name)
            }
        }
        .confirmationDialog(
            "Close “\(appState.pendingClose?.name ?? "")”?",
            isPresented: pendingCloseBinding,
            titleVisibility: .visible
        ) {
            Button("Save & Close") {
                Task { await appState.resolvePendingClose(save: true) }
            }
            Button("Discard Changes", role: .destructive) {
                Task { await appState.resolvePendingClose(save: false) }
            }
            Button("Cancel", role: .cancel) {
                appState.pendingClose = nil
            }
        } message: {
            Text("Unsaved changes will be lost if you discard them.")
        }
        .alert("Code Editor", isPresented: errorBinding) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    // MARK: - Content

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
            EmptyStateView(
                appState: appState,
                onOpenFolder: { appState.openFolder() },
                onNewFile: { appState.newFile() }
            )
        }
    }

    private var navigationTitle: String {
        if let document = appState.documentManager.activeDocument {
            return document.title
        }
        return appState.fileSystemManager.rootName
    }

    // MARK: - Toolbar

    /// Unified toolbar: identity in the middle, creation and panels at the trailing
    /// edge. Replaces the sidebar's hand-rolled header row.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            breadcrumb
        }

        ToolbarItemGroup(placement: .primaryAction) {
            createMenu

            Button {
                appState.toggleTerminal()
            } label: {
                Image(
                    systemName: appState.isTerminalVisible
                        ? "rectangle.bottomthird.inset.filled"
                        : "rectangle.bottomthird.inset")
            }
            .help(appState.isTerminalVisible ? "Hide Terminal (⌃`)" : "Show Terminal (⌃`)")
        }
    }

    /// The project-relative path of the active document, quiet and capped.
    @ViewBuilder
    private var breadcrumb: some View {
        let segments = appState.breadcrumb
        if segments.isEmpty {
            Text(appState.fileSystemManager.rootName)
                .font(Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            HStack(spacing: Metrics.Space.compact) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(segment)
                        .font(Typography.sectionHeader)
                        .foregroundStyle(
                            index == segments.count - 1 ? .primary : .secondary
                        )
                        .lineLimit(1)
                }
            }
        }
    }

    /// One create button with a menu, instead of two icon buttons. New items land
    /// beside the active document, or at the workspace root — the Xcode rule.
    private var createMenu: some View {
        Menu {
            Button {
                appState.requestCreation(kind: .file)
            } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                appState.requestCreation(kind: .folder)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
        }
        .help("New File (⌘N)")
        .disabled(appState.defaultCreateDirectory == nil)
    }

    // MARK: - Bindings

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.isSidebarVisible ? .all : .detailOnly },
            set: { appState.isSidebarVisible = ($0 != .detailOnly) }
        )
    }

    private var pendingCloseBinding: Binding<Bool> {
        Binding(
            get: { appState.pendingClose != nil },
            set: { if !$0 { appState.pendingClose = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }
}

#Preview {
    MainWindowView(appState: AppState())
        .frame(width: 1200, height: 800)
}
