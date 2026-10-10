import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// The window's single empty state, shown when no document is active.
///
/// Adapts to what is missing: with a workspace open it points at the sidebar, which
/// is where the action is; with nothing open it offers the two ways to start. The
/// previous UI showed both messages at once, one per pane, with different
/// capitalisation and duplicate buttons.
public struct EmptyStateView: View {
    let appState: AppState
    let onOpenFolder: () -> Void
    let onNewFile: () -> Void

    public init(
        appState: AppState,
        onOpenFolder: @escaping () -> Void,
        onNewFile: @escaping () -> Void
    ) {
        self.appState = appState
        self.onOpenFolder = onOpenFolder
        self.onNewFile = onNewFile
    }

    private var hasWorkspace: Bool { appState.fileSystemManager.rootURL != nil }

    public var body: some View {
        VStack(spacing: Metrics.Space.loose) {
            mark

            if hasWorkspace {
                Text("No Document Open")
                    .font(Typography.emptyTitle)
                    .foregroundStyle(appState.theme.text.color)

                Text("Select a file in the sidebar, or press ⇧⌘O to open one.")
                    .font(Typography.emptyBody)
                    .foregroundStyle(appState.theme.secondaryText.color)
            } else {
                Text("Open a Folder")
                    .font(Typography.emptyTitle)
                    .foregroundStyle(appState.theme.text.color)

                Text("Browse and edit a project, or start from an empty file.")
                    .font(Typography.emptyBody)
                    .foregroundStyle(appState.theme.secondaryText.color)

                actions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appState.theme.background.color)
    }

    /// The app mark: the code glyph on a soft accent plate. One memorable element,
    /// everything else stays quiet.
    private var mark: some View {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(appState.theme.chrome.accent.color)
            .frame(width: 72, height: 72)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.panel, style: .continuous)
                    .fill(appState.theme.chrome.accent.color.opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    /// One primary action; the secondary is visually and structurally subordinate.
    private var actions: some View {
        HStack(spacing: Metrics.Space.regular) {
            Button(action: onOpenFolder) {
                Label("Open Folder…", systemImage: "folder")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)

            Button(action: onNewFile) {
                Text("New File")
            }
            .controlSize(.large)
        }
        .padding(.top, Metrics.Space.compact)
    }
}
