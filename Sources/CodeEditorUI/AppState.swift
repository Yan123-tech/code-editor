import CodeEditorCore
import CodeEditorTerminal
import CodeEditorThemes
import SwiftUI

/// The app's shared state: open folder, documents, theme, editor preferences, terminal.
@MainActor
@Observable
public final class AppState {
    public private(set) var fileSystemManager: FileSystemManager
    public private(set) var documentManager: DocumentManager
    public var themeManager: ThemeManager
    public private(set) var editorState: EditorState
    public private(set) var terminal: TerminalSession

    // Chrome
    public var isSidebarVisible = true
    public var isTerminalVisible = false
    public var isStatusBarVisible = true

    public var errorMessage: String?

    /// A creation the user has requested but not yet named. Presented as one sheet
    /// regardless of whether the toolbar menu or a context menu requested it.
    public var pendingCreation: PendingCreation?

    /// A modified document the user asked to close. Presented as one confirmation
    /// regardless of whether the tab strip or the menu asked.
    public var pendingClose: CodeEditorCore.Document?

    public init() {
        let fileSystemManager = FileSystemManager()
        let themeManager = ThemeManager()
        let editorState = EditorState()
        themeManager.loadPersistedTheme()
        editorState.loadPersistedSettings()

        self.fileSystemManager = fileSystemManager
        self.documentManager = CodeEditorCore.DocumentManager()
        self.themeManager = themeManager
        self.editorState = editorState
        self.terminal = TerminalSession()
    }

    // MARK: - Theme

    public var theme: Theme { themeManager.currentTheme }

    // MARK: - Folder

    public func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.directoryURL = fileSystemManager.rootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(at: url)
    }

    public func openFolder(at url: URL) {
        fileSystemManager.setRoot(url)
        terminal.disconnect()
        terminal.workingDirectory = url
        terminal.clear()
    }

    // MARK: - Documents

    public func openFile(_ url: URL) {
        Task {
            do {
                try await openFileThrowing(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    public func openFileThrowing(_ url: URL) async throws -> CodeEditorCore.Document {
        try await documentManager.open(url)
    }

    public func newFile() {
        let document = CodeEditorCore.Document.untitled()
        documentManager.open(document)
    }

    public func saveActiveDocument() {
        guard let document = documentManager.activeDocument else { return }

        Task {
            if document.isUntitled {
                await promptForSaveLocation(for: document)
            } else {
                await performSave(document)
            }
        }
    }

    public func saveAllDocuments() {
        Task { await documentManager.saveAll() }
    }

    /// Prompt for a location, then save. Unsaved documents start as "Untitled N".
    public func promptForSaveLocation(for document: CodeEditorCore.Document) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName(for: document)
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.directoryURL = fileSystemManager.rootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        await performSave(document, to: url)
    }

    private func suggestedFileName(for document: CodeEditorCore.Document) -> String {
        if let existing = document.url { return existing.lastPathComponent }
        let base = documentManager.documents.filter { $0.isUntitled }.count
        return "Untitled\(base > 1 ? " \(base)" : "").\(document.language.fileExtensions.first ?? "txt")"
    }

    public func performSave(_ document: CodeEditorCore.Document, to url: URL? = nil) async {
        do {
            if let url {
                try await document.save(to: url)
            } else {
                try await document.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ask to close a document. Clean documents close immediately; modified ones
    /// are parked in `pendingClose` for the window's confirmation dialog.
    public func requestClose(_ document: CodeEditorCore.Document) {
        guard document.isModified else {
            documentManager.close(document)
            return
        }
        pendingClose = document
    }

    /// Resolve a pending close. `save` runs the save flow first; saving an untitled
    /// document opens a location prompt, and a cancelled prompt aborts the close.
    public func resolvePendingClose(save: Bool) async {
        guard let document = pendingClose else { return }
        pendingClose = nil

        if save {
            if document.isUntitled {
                await promptForSaveLocation(for: document)
                // A cancelled save panel leaves the document unsaved; keep it open.
                guard !document.isModified else { return }
            } else {
                await performSave(document)
                guard !document.isModified else { return }
            }
        }
        documentManager.close(document)
    }

    public func close(_ document: CodeEditorCore.Document) {
        requestClose(document)
    }

    // MARK: - Commands

    /// Segments of the active document's path relative to the workspace root, for
    /// the toolbar breadcrumb. Capped to the last three so deep paths stay legible.
    public var breadcrumb: [String] {
        guard let url = documentManager.activeDocument?.url else { return [] }
        let path = url.standardizedFileURL.path
        if let rootPath = fileSystemManager.rootURL?.standardizedFileURL.path,
            path.hasPrefix(rootPath + "/")
        {
            let segments = path.dropFirst(rootPath.count + 1).split(separator: "/").map(String.init)
            return Array(segments.suffix(3))
        }
        return [url.lastPathComponent]
    }

    /// Where new items land when no directory is given: beside the active
    /// document, or at the workspace root. The Xcode rule.
    public var defaultCreateDirectory: URL? {
        if let parent = documentManager.activeDocument?.url?.deletingLastPathComponent() {
            return parent
        }
        return fileSystemManager.rootURL
    }

    /// Queue a creation for naming. `directory` nil means `defaultCreateDirectory`.
    public func requestCreation(kind: NewItemKind, in directory: URL? = nil) {
        guard let directory = directory ?? defaultCreateDirectory else { return }
        pendingCreation = PendingCreation(kind: kind, directory: directory)
    }

    /// Create the pending item and open it if it is a file.
    public func performCreation(named name: String) {
        guard let pending = pendingCreation else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        Task {
            do {
                switch pending.kind {
                case .file:
                    try await fileSystemManager.createFile(named: trimmed, in: pending.directory)
                    openFile(pending.directory.appendingPathComponent(trimmed))
                case .folder:
                    try await fileSystemManager.createFolder(named: trimmed, in: pending.directory)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    public func toggleTerminal() {
        isTerminalVisible.toggle()
        if isTerminalVisible, !terminal.isConnected {
            terminal.connect()
        }
    }

    public func setTheme(named name: String) {
        themeManager.setTheme(named: name)
    }
}
