import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Top-level sidebar container hosting the navigator tabs (Project Files vs Search).
public struct SidebarContainerView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Navigator tab switcher
            Picker("Navigator", selection: $appState.activeSidebarTab) {
                Label("Files", systemImage: "folder")
                    .tag(SidebarTab.files)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarTab.search)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Metrics.Space.regular)
            .padding(.vertical, Metrics.Space.compact)
            .background(appState.theme.chrome.sidebarBackground.color)

            Divider()

            switch appState.activeSidebarTab {
            case .files:
                FileExplorerView(
                    fileSystemManager: appState.fileSystemManager,
                    theme: appState.theme,
                    activeDocumentURL: appState.documentManager.activeDocument?.url,
                    onOpenFile: { url in appState.openFile(url) },
                    onCreateIn: { directory, kind in
                        appState.requestCreation(kind: kind, in: directory)
                    }
                )
            case .search:
                WorkspaceSearchView(appState: appState)
            }
        }
        .background(appState.theme.chrome.sidebarBackground.color)
    }
}
