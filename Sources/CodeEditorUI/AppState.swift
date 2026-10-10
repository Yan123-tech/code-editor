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
    public private(set) var quickOpenIndex: QuickOpenIndex

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

    // Quick open
    public var isQuickOpenVisible = false
    public var quickOpenQuery = ""
    public private(set) var quickOpenResults: [QuickOpenMatch] = []

    /// Terminal panel height in points, persisted. Drag-resized, never fixed.
    public var terminalHeight: Double {
        didSet {
            guard oldValue != terminalHeight else { return }
            UserDefaults.standard.set(terminalHeight, forKey: Self.terminalHeightKey)
        }
    }

    private static let terminalHeightKey = "CodeEditor.terminalHeight"
    private static let terminalHeightDefault: Double = 220
    private static let terminalHeightRange: ClosedRange<Double> = 120...600

    public init(restoreSession: Bool = true) {
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
        self.quickOpenIndex = QuickOpenIndex()

        let stored = UserDefaults.standard.double(forKey: Self.terminalHeightKey)
        self.terminalHeight =
            (Self.terminalHeightRange).contains(stored)
            ? stored
            : Self.terminalHeightDefault

        documentManager.delegate = self
        if restoreSession {
            restoreFromSession()
        }
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
        quickOpenIndex.reindex(root: url)
        persistSession()
    }

    // MARK: - Session

    /// What a relaunch would restore right now.
    private var sessionSnapshot: SessionSnapshot {
        SessionSnapshot(
            rootPath: fileSystemManager.rootURL?.standardizedFileURL.path,
            openPaths: documentManager.documents.compactMap { $0.url?.standardizedFileURL.path },
            activePath: documentManager.activeDocument?.url?.standardizedFileURL.path
        )
    }

    /// Persist the session whenever the set of things worth restoring changes.
    private func persistSession() {
        SessionStore.save(sessionSnapshot)
    }

    /// Reopen the workspace and tabs from the last session, if any. Files that no
    /// longer exist are skipped silently; a missing root clears the snapshot.
    private func restoreFromSession() {
        guard let snapshot = SessionStore.load() else { return }

        if let rootPath = snapshot.rootPath {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: rootPath) {
                fileSystemManager.setRoot(root)
                quickOpenIndex.reindex(root: root)
                terminal.workingDirectory = root
            } else {
                SessionStore.clear()
            }
        }

        guard !snapshot.openPaths.isEmpty else { return }
        Task { [weak self] in
            var restored: [CodeEditorCore.Document] = []
            for path in snapshot.openPaths {
                guard let self, FileManager.default.fileExists(atPath: path) else { continue }
                if let document = try? await self.openFileThrowing(URL(fileURLWithPath: path)) {
                    restored.append(document)
                }
            }
            if let activePath = snapshot.activePath,
                let active = restored.first(where: { $0.url?.standardizedFileURL.path == activePath })
            {
                self?.documentManager.activate(active)
            }
        }
    }

    // MARK: - Quick open

    /// Re-run the quick-open search. Call on every keystroke; the matcher is
    /// linear in the index and the index caps itself.
    public func updateQuickOpenResults() {
        guard isQuickOpenVisible else {
            quickOpenResults = []
            return
        }
        quickOpenResults = quickOpenIndex.search(quickOpenQuery, limit: 25)
    }

    public func toggleQuickOpen() {
        isQuickOpenVisible.toggle()
        if isQuickOpenVisible {
            quickOpenQuery = ""
            if let root = fileSystemManager.rootURL, quickOpenIndex.entries.isEmpty {
                quickOpenIndex.reindex(root: root)
            }
            updateQuickOpenResults()
        }
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
        let document = try await documentManager.open(url)
        persistSession()
        return document
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

    /// Save every modified document and report whether the job actually finished.
    ///
    /// Returns false when anything was abandoned — a cancelled location panel, a failed
    /// write. The quit handler treats false as "do not proceed": after this returns, a
    /// document that is still modified still holds the user's work.
    ///
    /// The decision itself belongs to `DocumentManager`, which can be tested without a
    /// window; only the saving needs the panels, which is why it is injected.
    @discardableResult
    public func saveAllModified() async -> Bool {
        await documentManager.saveAllModified { document in
            if document.isUntitled {
                await self.promptForSaveLocation(for: document)
            } else {
                await self.performSave(document)
            }
        }
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

// MARK: - DocumentManagerDelegate

extension AppState: DocumentManagerDelegate {
    public func didOpenDocument(_ document: CodeEditorCore.Document) {
        persistSession()
    }

    public func didCloseDocument(_ document: CodeEditorCore.Document) {
        persistSession()
    }
}
