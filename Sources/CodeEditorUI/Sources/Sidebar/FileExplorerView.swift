import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Recursive file tree for the sidebar.
public struct FileExplorerView: View {
    @Bindable var fileSystemManager: FileSystemManager
    let theme: Theme
    let onOpenFile: (URL) -> Void

    /// Directory that "New File/Folder" targets; defaults to the root.
    @State private var targetFolder: FileSystemItem?
    @State private var sheet: NewItemSheet?
    @State private var renaming: FileSystemItem?
    @State private var errorMessage: String?

    public init(
        fileSystemManager: FileSystemManager,
        theme: Theme,
        onOpenFile: @escaping (URL) -> Void
    ) {
        self.fileSystemManager = fileSystemManager
        self.theme = theme
        self.onOpenFile = onOpenFile
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.separator.color)

            Group {
                if let root = fileSystemManager.rootURL {
                    list(for: root)
                } else {
                    emptyState
                }
            }
        }
        .frame(minWidth: 180, idealWidth: 240, maxWidth: 420)
        .background(theme.background.color)
        .sheet(item: $sheet) { sheet in
            NewItemSheetView(kind: sheet.kind) { name in
                create(sheet.kind, named: name)
            }
        }
        .sheet(item: $renaming) { item in
            RenameSheetView(current: item.name) { newName in
                Task { await rename(item, to: newName) }
            }
        }
        .alert("File Explorer", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 4) {
            Text(fileSystemManager.rootName)
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.text.color)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button {
                sheet = NewItemSheet(kind: .file)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New File")

            Button {
                sheet = NewItemSheet(kind: .folder)
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New Folder")
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundColor(theme.secondaryText.color)
            Text("No folder open")
                .font(.caption)
                .foregroundColor(theme.secondaryText.color)
            Button("Open Folder…") {
                NotificationCenter.default.post(name: .codeEditorOpenFolder, object: nil)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(for root: URL) -> some View {
        List(selection: selectionBinding) {
            ForEach(rows(from: root)) { row in
                rowView(row.item)
                    .tag(row.item)
                    .padding(.leading, CGFloat(row.depth) * 12)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.background.color)
    }

    /// Flatten the expanded tree into indentable rows.
    private func rows(from directory: URL, depth: Int = 0) -> [FileRow] {
        guard depth < 32 else { return [] }

        return fileSystemManager.children(of: directory).flatMap { item -> [FileRow] in
            guard item.isDirectory else { return [FileRow(item: item, depth: depth)] }

            var result: [FileRow] = [FileRow(item: item, depth: depth)]
            if fileSystemManager.isExpanded(item.url) {
                result.append(contentsOf: rows(from: item.url, depth: depth + 1))
            }
            return result
        }
    }

    private func rowView(_ item: FileSystemItem) -> some View {
        let isTarget = targetFolder?.url == item.url

        return HStack(spacing: 4) {
            if item.isDirectory {
                Button {
                    fileSystemManager.toggleExpansion(of: item)
                } label: {
                    Image(systemName: fileSystemManager.isExpanded(item.url) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(theme.secondaryText.color)
                }
                .buttonStyle(.plain)
                .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            Image(systemName: item.iconName)
                .font(.system(size: 11))
                .foregroundColor(item.isDirectory ? theme.keyword.color : theme.secondaryText.color)
                .frame(width: 14)

            Text(item.name)
                .font(.system(size: 12))
                .foregroundColor(theme.text.color)
                .lineLimit(1)
                .truncationMode(.middle)

            if isTarget {
                Image(systemName: "target")
                    .font(.system(size: 9))
                    .foregroundColor(theme.secondaryText.color)
                    .help("New items will be created here")
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.isDirectory {
                fileSystemManager.toggleExpansion(of: item)
            } else {
                onOpenFile(item.url)
            }
        }
        .onTapGesture {
            if item.isDirectory {
                targetFolder = item
            }
        }
        .contextMenu {
            Button("New File Here") {
                targetFolder = item
                sheet = NewItemSheet(kind: .file)
            }
            Button("New Folder Here") {
                targetFolder = item
                sheet = NewItemSheet(kind: .folder)
            }
            if !item.isDirectory {
                Divider()
                Button("Rename…") { renaming = item }
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(item) }
            }
        }
    }

    // MARK: - Actions

    private var selectionBinding: Binding<FileSystemItem?> {
        Binding(
            get: { targetFolder },
            set: { targetFolder = $0 }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || fileSystemManager.errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func create(_ kind: NewItemKind, named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        let directory = targetFolder?.url ?? fileSystemManager.rootURL
        guard !name.isEmpty, let directory else { return }

        Task {
            do {
                switch kind {
                case .file:
                    try await fileSystemManager.createFile(named: name, in: directory)
                    onOpenFile(directory.appendingPathComponent(name))
                case .folder:
                    try await fileSystemManager.createFolder(named: name, in: directory)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

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

// MARK: - Tree rows

/// A single visible row: the item plus how deep it sits in the expanded tree.
private struct FileRow: Identifiable {
    let item: FileSystemItem
    let depth: Int

    var id: URL { item.url }
}

// MARK: - Sheets

private enum NewItemKind {
    case file
    case folder

    var title: String {
        switch self {
        case .file: return "New File"
        case .folder: return "New Folder"
        }
    }

    var placeholder: String {
        switch self {
        case .file: return "File name"
        case .folder: return "Folder name"
        }
    }
}

private struct NewItemSheet: Identifiable {
    let id = UUID()
    var kind: NewItemKind
}

private struct NewItemSheetView: View {
    let kind: NewItemKind
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.title).font(.headline)

            TextField(kind.placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        dismiss()
    }
}

private struct RenameSheetView: View {
    let current: String
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(current: String, onRename: @escaping (String) -> Void) {
        self.current = current
        self.onRename = onRename
        _name = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename “\(current)”").font(.headline)

            TextField("New name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == current)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func submit() {
        onRename(name)
        dismiss()
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by the sidebar to ask the app to present an open-folder panel.
    public static let codeEditorOpenFolder = Notification.Name("CodeEditor.openFolder")

    /// Posted by the app with an array of `URL`s to open in the editor.
    public static let codeEditorOpenFiles = Notification.Name("CodeEditor.openFiles")
}
