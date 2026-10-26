import CodeEditorCore
import CodeEditorLSP
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
    public var isSettingsVisible = false

    public var errorMessage: String?

    /// A creation the user has requested but not yet named. Presented as one sheet
    /// regardless of whether the toolbar menu or a context menu requested it.
    public var pendingCreation: PendingCreation?

    /// A modified document the user asked to close. Presented as one confirmation
    /// regardless of whether the tab strip or the menu asked.
    public var pendingClose: CodeEditorCore.Document?

    /// A document whose file changed on disk since it was opened, surfaced as a
    /// confirmation dialog offering Revert / Save Anyway instead of a silent overwrite.
    public var pendingExternalChange: CodeEditorCore.Document?

    // Quick open
    public var isQuickOpenVisible = false
    public var quickOpenQuery = ""
    public private(set) var quickOpenResults: [QuickOpenMatch] = []

    // Recent Projects
    public var recentProjects: [RecentProject] = []

    // Diagnostic navigation
    public var diagnosticJumpRequest: DiagnosticJumpRequest?

    /// Terminal panel height in points, persisted. Drag-resized, never fixed.
    public var terminalHeight: Double

    public func persistTerminalHeight() {
        UserDefaults.standard.set(terminalHeight, forKey: Self.terminalHeightKey)
    }

    private static let terminalHeightKey = "CodeEditor.terminalHeight"
    private static let terminalHeightDefault: Double = 220
    private static let terminalHeightRange: ClosedRange<Double> = 120...600

    public init(restoreSession: Bool = false) {
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
        self.recentProjects = RecentProjectsStore.load()

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
        disconnectLanguageServers()
        terminal.disconnect()
        terminal.workingDirectory = url
        terminal.projectRootDirectory = url
        terminal.clear()
        quickOpenIndex.reindex(root: url)
        RecentProjectsStore.record(url: url)
        recentProjects = RecentProjectsStore.load()
        persistSession()
    }

    public func removeRecentProject(_ project: RecentProject) {
        RecentProjectsStore.remove(url: project.url)
        recentProjects = RecentProjectsStore.load()
    }

    public func clearRecentProjects() {
        RecentProjectsStore.clear()
        recentProjects = []
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
                terminal.projectRootDirectory = root
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

    /// Save every modified document through `performSave`, so a file that changed on disk
    /// surfaces the same Revert / Save-Anyway dialog as a single-document save.
    public func saveAllDocuments() {
        Task {
            for document in documentManager.documents where document.isModified {
                await performSave(document)
            }
        }
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
        if editorState.formatOnSave && document.language.identifier == "go" {
            if let formatted = GoFormatter.format(document.content), formatted != document.content {
                document.setContent(formatted)
            }
        }
        do {
            if let url {
                try await document.save(to: url)
            } else {
                try await document.save()
            }
        } catch DocumentError.changedOnDisk {
            pendingExternalChange = document
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reload `document` from disk, resolving a pending external-change prompt. The
    /// on-disk version wins.
    public func revertDocument(_ document: CodeEditorCore.Document) async {
        pendingExternalChange = nil
        do {
            try await document.revert()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Overwrite `document`, ignoring an external change. Resolves the pending prompt.
    public func saveAnyway(_ document: CodeEditorCore.Document) async {
        pendingExternalChange = nil
        do {
            try await document.save(force: true)
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

    /// Queue a creation for naming. `directory` nil means `defaultCreateDirectory` .
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

    // MARK: - Development Actions

    public func formatActiveDocument() {
        guard let document = documentManager.activeDocument else { return }
        if document.language.identifier == "go" {
            if let formatted = GoFormatter.format(document.content), formatted != document.content {
                document.setContent(formatted)
            }
        }
    }

    public func runProject() {
        if !isTerminalVisible {
            isTerminalVisible = true
        }
        guard let root = fileSystemManager.rootURL else { return }
        terminal.workingDirectory = root
        terminal.projectRootDirectory = root
        if !terminal.isConnected {
            terminal.connect()
        }
        let goMod = root.appendingPathComponent("go.mod")
        let isGo =
            FileManager.default.fileExists(atPath: goMod.path)
            || documentManager.activeDocument?.language.identifier == "go"
        if isGo {
            terminal.submit("go run .")
        } else {
            terminal.submit("make run")
        }
    }

    public func testProject() {
        if !isTerminalVisible {
            isTerminalVisible = true
        }
        guard let root = fileSystemManager.rootURL else { return }
        terminal.workingDirectory = root
        terminal.projectRootDirectory = root
        if !terminal.isConnected {
            terminal.connect()
        }
        let goMod = root.appendingPathComponent("go.mod")
        let isGo =
            FileManager.default.fileExists(atPath: goMod.path)
            || documentManager.activeDocument?.language.identifier == "go"
        if isGo {
            terminal.submit("go test -v ./...")
        } else {
            terminal.submit("make test")
        }
    }

    // MARK: - Language servers

    /// One lazily-started server per language identifier for the current workspace.
    /// Clients are `nil` once a crash has been observed; they are reconnected on the
    /// next `languageServer(for:)` call, after the backoff cooldown.
    @ObservationIgnored
    private var languageServers: [String: LSPClient] = [:]

    /// Last time a server for a language failed to start, for the backoff cooldown.
    @ObservationIgnored
    private var serverFailedAt: [String: Date] = [:]

    /// The minimum cool-down between reconnect attempts after a failure, to avoid
    /// respawning a crashing server on every keystroke.
    private static let reconnectCooldown: TimeInterval = 5.0

    /// The language server for `languageId`, starting it on first use for the current
    /// workspace. Reconnects after a crash once the cooldown has elapsed.
    ///
    /// Returns `nil` when no server is registered for the language, the workspace has no
    /// root, the server failed to initialize (its `lastError` is surfaced via
    /// `errorMessage`), or a recent failure is still inside the cool-down window.
    public func languageServer(for languageId: String) async -> LSPClient? {
        if let existing = languageServers[languageId], existing.isReady {
            return existing
        }

        // In the cool-down window after a failure, don't respawn.
        if let last = serverFailedAt[languageId],
            Date().timeIntervalSince(last) < Self.reconnectCooldown
        {
            return nil
        }
        serverFailedAt[languageId] = nil

        // Drop a crashed/stale client so we can reconnect.
        if let existing = languageServers[languageId], !existing.isReady {
            Task { await existing.disconnect() }
            languageServers[languageId] = nil
        }

        guard let descriptor = LanguageServerRegistry.descriptor(for: languageId) else {
            return nil
        }

        let client = LSPClient(descriptor: descriptor, rootURL: fileSystemManager.rootURL)
        await client.connect()
        if client.isReady {
            languageServers[languageId] = client
            errorMessage = nil
            return client
        } else {
            serverFailedAt[languageId] = Date()
            errorMessage = client.lastError ?? "Could not start \(descriptor.displayName)."
            return nil
        }
    }

    // MARK: - AI Completion

    /// Fetches available models from the configured OpenAI-compatible API base URL.
    public func fetchAIModels() async {
        editorState.aiIsFetchingModels = true
        editorState.aiFetchError = nil
        do {
            let models = try await OpenAIClient.shared.fetchModels(
                baseURL: editorState.aiBaseURL,
                apiKey: editorState.aiApiKey
            )
            editorState.setAIAvailableModels(models)
            if !models.isEmpty && !models.contains(editorState.aiModel) {
                if let preferred = models.first(where: {
                    $0.contains("gpt-4o") || $0.contains("coder") || $0.contains("claude")
                }) {
                    editorState.setAIModel(preferred)
                } else if let first = models.first {
                    editorState.setAIModel(first)
                }
            }
            editorState.aiIsFetchingModels = false
        } catch {
            editorState.aiIsFetchingModels = false
            editorState.aiFetchError = (error as NSError).localizedDescription
        }
    }

    // MARK: - Diagnostic navigation

    /// Navigates the editor to the specified diagnostic, focusing the document if needed.
    public func jumpTo(diagnostic: DocumentDiagnostic, in document: CodeEditorCore.Document? = nil) {
        if let doc = document, documentManager.activeDocument?.id != doc.id {
            documentManager.activate(doc)
        }
        diagnosticJumpRequest = DiagnosticJumpRequest(diagnostic: diagnostic)
    }

    /// Tear down every language server. Call on workspace switch and on quit.
    public func disconnectLanguageServers() {
        let clients = Array(languageServers.values)
        languageServers.removeAll()
        serverFailedAt.removeAll()
        for client in clients {
            Task { await client.disconnect() }
        }
    }
}

/// Carries a diagnostic jump target with a unique identity so repeat clicks trigger.
public struct DiagnosticJumpRequest: Equatable, Sendable {
    public let id: UUID
    public let diagnostic: DocumentDiagnostic

    public init(diagnostic: DocumentDiagnostic) {
        self.id = UUID()
        self.diagnostic = diagnostic
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
