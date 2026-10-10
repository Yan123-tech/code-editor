import Foundation

/// A language server the editor knows how to launch.
public struct LanguageServerDescriptor: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let command: [String]
    /// Language identifiers this server handles, matching `Language.identifier`.
    public let languageIdentifiers: Set<String>

    public init(id: String, displayName: String, command: [String], languageIdentifiers: Set<String>) {
        self.id = id
        self.displayName = displayName
        self.command = command
        self.languageIdentifiers = languageIdentifiers
    }
}

/// Known servers. Paths are resolved at launch time so a missing server is a clear error
/// rather than a silent no-op.
public enum LanguageServerRegistry {
    /// Path to Xcode's bundled `sourcekit-lsp`, if present.
    public static var sourceKitLSPPath: String? {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",
            "/Library/Developer/CommandLineTools/usr/bin/sourcekit-lsp",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func descriptor(for language: String) -> LanguageServerDescriptor? {
        switch language {
        case "swift":
            guard let path = sourceKitLSPPath else { return nil }
            return LanguageServerDescriptor(
                id: "sourcekit-lsp",
                displayName: "SourceKit-LSP",
                command: [path],
                languageIdentifiers: ["swift"]
            )
        default:
            return nil
        }
    }

    public static var allDescriptors: [LanguageServerDescriptor] {
        ["swift"].compactMap { descriptor(for: $0) }
    }
}

// MARK: - LSPClient

/// Drives a single language server for a single document.
///
/// Bring the client up with `connect()`, which starts the process and completes the
/// initialize handshake, then use `openDocument(uri:languageId:content:)`,
/// `completion(at:uri:)` and `hover(at:uri:)`. Diagnostics arrive asynchronously and are
/// published through `onDiagnosticsChanged`.
@MainActor
@Observable
public final class LSPClient {
    // State
    public private(set) var isConnected = false
    public private(set) var isReady = false
    public private(set) var serverCapabilities: ServerCapabilities?
    public private(set) var lastError: String?
    public private(set) var diagnosticsByURI: [String: [Diagnostic]] = [:]

    /// Called whenever a server publishes diagnostics for a document.
    public var onDiagnosticsChanged: ((String, [Diagnostic]) -> Void)?

    public let descriptor: LanguageServerDescriptor
    public let rootURL: URL?

    private let transport = JSONRPCTransport()

    // Internal bookkeeping, not view-facing state.
    @ObservationIgnored private var openURIs = Set<String>()
    @ObservationIgnored private var versions: [String: Int] = [:]

    public init(descriptor: LanguageServerDescriptor, rootURL: URL?) {
        self.descriptor = descriptor
        self.rootURL = rootURL
    }

    // MARK: - Lifecycle

    /// Start the server and complete the initialize handshake.
    public func connect() async {
        guard !isConnected else { return }

        do {
            try await transport.start(descriptor.command, workingDirectory: rootURL)
            isConnected = true
            lastError = nil

            await transport.setDisconnectionHandler { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleTransportDisconnect()
                }
            }

            await transport.onNotification { method, params in
                Task { @MainActor [weak self] in
                    self?.handleNotification(method: method, params: params)
                }
            }

            let result: InitializeResult = try await transport.request(
                method: "initialize",
                params: InitializeParams(
                    rootURI: rootURL?.absoluteString,
                    capabilities: .default,
                    workspaceFolders: rootURL.map {
                        [WorkspaceFolder(uri: $0.absoluteString, name: $0.lastPathComponent)]
                    }
                ),
                as: InitializeResult.self
            )

            serverCapabilities = result.capabilities
            try await transport.notify(method: "initialized", params: EmptyParams())
            isReady = true
        } catch {
            isConnected = false
            isReady = false
            lastError = error.localizedDescription
        }
    }

    public func disconnect() async {
        guard isConnected else { return }
        try? await transport.notify(method: "exit", params: nil)
        await transport.stop()
        isConnected = false
        isReady = false
        serverCapabilities = nil
        openURIs.removeAll()
        versions.removeAll()
    }

    /// Called by the transport when the server process exits unexpectedly. Marks the
    /// client not-ready so `languageServer(for:)` will drop and reconnect on the next
    /// request, rather than leaving callers parked on a dead connection.
    private func handleTransportDisconnect() {
        guard isConnected else { return }
        isConnected = false
        isReady = false
        serverCapabilities = nil
        lastError = "SourceKit-LSP stopped responding."
    }

    // MARK: - Document synchronization

    public func openDocument(uri: String, languageId: String, content: String) async {
        guard isReady else { return }
        do {
            try await transport.notify(
                method: "textDocument/didOpen",
                params: DidOpenParams(
                    textDocument: TextDocumentItem(uri: uri, languageId: languageId, version: 1, text: content)
                )
            )
            openURIs.insert(uri)
            versions[uri] = 1
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func updateDocument(uri: String, content: String) async {
        guard isReady, openURIs.contains(uri) else { return }
        let version = (versions[uri] ?? 0) + 1
        do {
            try await transport.notify(
                method: "textDocument/didChange",
                params: DidChangeParams(
                    textDocument: VersionedTextDocumentIdentifier(uri: uri, version: version),
                    contentChanges: [TextDocumentContentChangeEvent(text: content)]
                )
            )
            versions[uri] = version
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func closeDocument(uri: String) async {
        guard isReady, openURIs.contains(uri) else { return }
        try? await transport.notify(
            method: "textDocument/didClose",
            params: DidCloseParams(textDocument: TextDocumentIdentifier(uri: uri))
        )
        openURIs.remove(uri)
        versions[uri] = nil
        diagnosticsByURI[uri] = nil
    }

    // MARK: - Language features

    public func completion(at position: Position, uri: String) async throws -> [CompletionItem] {
        guard isReady else { throw TransportError.notConnected }
        return try await transport.request(
            method: "textDocument/completion",
            params: CompletionParams(
                textDocument: TextDocumentIdentifier(uri: uri),
                position: position,
                context: CompletionContext(triggerKind: .invoked)
            ),
            as: CompletionList.self
        ).items
    }

    public func hover(at position: Position, uri: String) async throws -> Hover? {
        guard isReady else { throw TransportError.notConnected }
        return try await transport.request(
            method: "textDocument/hover",
            params: HoverParams(textDocument: TextDocumentIdentifier(uri: uri), position: position),
            as: Hover.self
        )
    }

    public func definition(at position: Position, uri: String) async throws -> Location? {
        guard isReady else { throw TransportError.notConnected }
        return try await transport.request(
            method: "textDocument/definition",
            params: HoverParams(textDocument: TextDocumentIdentifier(uri: uri), position: position),
            as: LocationResponse.self
        ).location
    }

    public func workspaceSymbols(query: String) async throws -> [WorkspaceSymbol] {
        guard isReady else { throw TransportError.notConnected }
        let response: [WorkspaceSymbol] = try await transport.request(
            method: "workspace/symbol",
            params: WorkspaceSymbolParams(query: query),
            as: [WorkspaceSymbol].self
        )
        return response
    }

    public func diagnostics(for uri: String) -> [Diagnostic] {
        diagnosticsByURI[uri] ?? []
    }

    // MARK: - Notifications

    private func handleNotification(method: String, params: JSONValue) {
        switch method {
        case "textDocument/publishDiagnostics":
            guard
                let payload = try? JSONDecoder().decode(
                    PublishDiagnosticsPayload.self,
                    from: JSONEncoder().encode(params)
                )
            else { return }
            diagnosticsByURI[payload.uri] = payload.diagnostics
            onDiagnosticsChanged?(payload.uri, payload.diagnostics)

        case "window/logMessage", "window/showMessage":
            if let text = (try? params.decode(as: LogMessagePayload.self, using: JSONDecoder()))?.message {
                lastError = text
            }

        default:
            break
        }
    }
}

// MARK: - Notification payloads

struct EmptyParams: Encodable {}

struct DidOpenParams: Encodable {
    let textDocument: TextDocumentItem
}

struct DidChangeParams: Encodable {
    let textDocument: VersionedTextDocumentIdentifier
    let contentChanges: [TextDocumentContentChangeEvent]
}

struct DidCloseParams: Encodable {
    let textDocument: TextDocumentIdentifier
}

struct CompletionParams: Encodable {
    let textDocument: TextDocumentIdentifier
    let position: Position
    let context: CompletionContext
}

struct CompletionContext: Encodable {
    let triggerKind: CompletionTriggerKind
    var triggerCharacter: String?
}

struct HoverParams: Encodable {
    let textDocument: TextDocumentIdentifier
    let position: Position
}

struct WorkspaceSymbolParams: Encodable {
    let query: String
}

struct PublishDiagnosticsPayload: Decodable {
    let uri: String
    let diagnostics: [Diagnostic]
}

struct LogMessagePayload: Decodable {
    let message: String
}

/// `textDocument/definition` may return a single location or an array.
struct LocationResponse: Decodable {
    let location: Location?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(Location.self) {
            location = single
        } else if let many = try? decoder.singleValueContainer().decode([Location].self) {
            location = many.first
        } else {
            location = nil
        }
    }
}
