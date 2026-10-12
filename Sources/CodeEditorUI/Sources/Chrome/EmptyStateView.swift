import AppKit
import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// The window's single empty state, shown when no document is active.
///
/// Adapts to what is missing: with a workspace open it points at the sidebar;
/// with nothing open it presents the Welcome Hub with quick actions and Recent Projects.
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
                Text("Code Editor")
                    .font(Typography.emptyTitle)
                    .foregroundStyle(appState.theme.text.color)

                Text("Open a folder to start developing, or pick from recent projects.")
                    .font(Typography.emptyBody)
                    .foregroundStyle(appState.theme.secondaryText.color)

                actions

                recentProjectsSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appState.theme.background.color)
    }

    /// The app mark: the code glyph on a soft accent plate.
    private var mark: some View {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(appState.theme.chrome.accent.color)
            .frame(width: 64, height: 64)
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

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.compact) {
            HStack {
                Text("Recent Projects")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appState.theme.secondaryText.color)
                Spacer()
                if !appState.recentProjects.isEmpty {
                    Button("Clear") {
                        appState.clearRecentProjects()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(appState.theme.secondaryText.color)
                }
            }
            .padding(.horizontal, Metrics.Space.compact)

            if appState.recentProjects.isEmpty {
                Text("No recent projects")
                    .font(.system(size: 12))
                    .foregroundStyle(appState.theme.secondaryText.color.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Metrics.Space.regular)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.recentProjects) { project in
                            RecentProjectRow(
                                project: project,
                                theme: appState.theme,
                                onSelect: {
                                    appState.openFolder(at: project.url)
                                },
                                onRemove: {
                                    appState.removeRecentProject(project)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(Metrics.Space.regular)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.panel, style: .continuous)
                .fill(appState.theme.chrome.overlayBackground.color.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.panel, style: .continuous)
                .strokeBorder(appState.theme.chrome.border.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - RecentProjectRow

private struct RecentProjectRow: View {
    let project: RecentProject
    let theme: Theme
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Metrics.Space.compact) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.chrome.accent.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text.color)
                        .lineLimit(1)

                    Text(displayPath(for: project.url))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(relativeDateString(for: project.lastOpened))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryText.color.opacity(0.8))
            }
            .padding(.horizontal, Metrics.Space.regular)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous)
                    .fill(isHovered ? theme.chrome.rowHover.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open") { onSelect() }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.url.path)
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.url.path, forType: .string)
            }
            Divider()
            Button("Remove from Recents") { onRemove() }
        }
    }

    private func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
