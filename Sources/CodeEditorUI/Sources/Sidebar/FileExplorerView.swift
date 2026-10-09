import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Recursive file tree for the sidebar.
///
/// Clicking a row selects it. Selecting a file opens it in the editor — the Xcode
/// navigator behaviour — and selecting a folder makes it the target of the toolbar's
/// create menu. The disclosure triangle (and only the triangle) toggles expansion,
/// which is what every Mac outline view does; the previous version required a
/// double-click and used a single click to set an invisible create-target.
///
/// The active document is emphasised (bold name, accent icon) and revealed by
/// expanding its ancestors whenever it changes.
public struct FileExplorerView: View {
    @Bindable var fileSystemManager: FileSystemManager
    let theme: Theme
    let activeDocumentURL: URL?
    let onOpenFile: (URL) -> Void
    let onCreateIn: (URL, NewItemKind) -> Void

    @State private var selection: FileSystemItem?
    @State private var renaming: FileSystemItem?
    @State private var deleting: FileSystemItem?
    @State private var errorMessage: String?

    public init(
        fileSystemManager: FileSystemManager,
        theme: Theme,
        activeDocumentURL: URL?,
        onOpenFile: @escaping (URL) -> Void,
        onCreateIn: @escaping (URL, NewItemKind) -> Void
    ) {
        self.fileSystemManager = fileSystemManager
        self.theme = theme
        self.activeDocumentURL = activeDocumentURL
        self.onOpenFile = onOpenFile
        self.onCreateIn = onCreateIn
    }

    public var body: some View {
        Group {
            if let root = fileSystemManager.rootURL {
                list(for: root)
            } else {
                emptyState
            }
        }
        .task(id: activeDocumentURL) {
            await revealActiveDocument()
        }
        .sheet(item: $renaming) { item in
            RenameSheetView(current: item.name) { newName in
                Task { await rename(item, to: newName) }
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: deletingBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = deleting { Task { await delete(item) } }
            }
        } message: {
            Text("The item is deleted immediately. This cannot be undone.")
        }
        .alert("File Explorer", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                fileSystemManager.clearError()
            }
        } message: {
            Text(errorMessage ?? fileSystemManager.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    /// One quiet line when no folder is open. The canvas owns the empty-state
    /// experience — a second one here competed with it.
    private var emptyState: some View {
        Text("No folder open")
            .font(Typography.emptyBody)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(for root: URL) -> some View {
        List(selection: $selection) {
            ForEach(
                FileOutline.rows(
                    from: root,
                    children: fileSystemManager.children(of:),
                    isExpanded: fileSystemManager.isExpanded
                )
            ) { row in
                rowView(row.item)
                    .tag(row.item)
                    .padding(.leading, CGFloat(row.depth) * Metrics.treeIndentPerLevel)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, newValue in
            // Selection drives activation, as it does in Xcode's navigator:
            // landing on a file opens it, landing on a folder expands it. Arrowing
            // through the tree does the same, which is why the expansion lives
            // here rather than on a tap gesture that `List` would swallow.
            guard let newValue else { return }
            activate(newValue)
        }
        .onKeyPress(.return) {
            // Return on the already-selected row changes nothing, so this is the
            // only way to re-activate the current row.
            if let selection { activate(selection) }
            return .handled
        }
    }

    /// What selecting a row does: files open, folders toggle.
    private func activate(_ item: FileSystemItem) {
        if item.isDirectory {
            fileSystemManager.toggleExpansion(of: item)
        } else {
            onOpenFile(item.url)
        }
    }

    private func rowView(_ item: FileSystemItem) -> some View {
        let isActiveDocument = item.url == activeDocumentURL

        return HStack(spacing: Metrics.Space.compact) {
            disclosureControl(for: item)

            Image(systemName: item.iconName)
                .font(Typography.sidebarRow)
                .foregroundStyle(iconColor(for: item, isActiveDocument: isActiveDocument))
                .frame(width: 16)

            Text(item.name)
                .font(Typography.sidebarRow)
                .fontWeight(isActiveDocument ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            if item.isDirectory {
                Button {
                    onCreateIn(item.url, .file)
                } label: {
                    Label("New File Here", systemImage: "doc.badge.plus")
                }
                Button {
                    onCreateIn(item.url, .folder)
                } label: {
                    Label("New Folder Here", systemImage: "folder.badge.plus")
                }
                Divider()
            }
            Button {
                renaming = item
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Divider()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                deleting = item
            } label: {
                Label("Delete…", systemImage: "trash")
            }
        }
    }

    /// The disclosure chevron. Decorative, not a control: selecting the row is what
    /// expands a folder, so a second tap target here would toggle it twice.
    @ViewBuilder
    private func disclosureControl(for item: FileSystemItem) -> some View {
        if item.isDirectory {
            Image(systemName: fileSystemManager.isExpanded(item.url) ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    private func iconColor(for item: FileSystemItem, isActiveDocument: Bool) -> Color {
        if isActiveDocument {
            return theme.chrome.accent.color
        }
        return item.isDirectory ? theme.chrome.accent.color.opacity(0.7) : .secondary
    }

    // MARK: - Reveal and selection

    /// Reveal and emphasise the active document whenever it changes, including on
    /// first appearance.
    private func revealActiveDocument() async {
        guard let url = activeDocumentURL else { return }
        await fileSystemManager.reveal(url)

        let parent = url.deletingLastPathComponent()
        selection = fileSystemManager.children(of: parent).first { $0.url == url } ?? selection
    }

    // MARK: - Bindings

    private var deletingBinding: Binding<Bool> {
        Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )
    }

    /// Dismissing the alert must clear both error copies. Clearing only the view's
    /// own copy left the manager's set, so the alert re-presented immediately.
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || fileSystemManager.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                    fileSystemManager.clearError()
                }
            }
        )
    }

    // MARK: - Actions

    private func rename(_ item: FileSystemItem, to newName: String) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != item.name else { return }
        do {
            try await fileSystemManager.rename(item, to: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: FileSystemItem) async {
        do {
            try await fileSystemManager.delete(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by the sidebar to ask the app to present an open-folder panel.
    public static let codeEditorOpenFolder = Notification.Name("CodeEditor.openFolder")

    /// Posted by the app with an array of `URL`s to open in the editor.
    public static let codeEditorOpenFiles = Notification.Name("CodeEditor.openFiles")
}
