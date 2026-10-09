import Foundation

// MARK: - LSP primitives

public struct Position: Codable, Equatable, Sendable {
    public var line: Int
    public var character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct Range: Codable, Equatable, Sendable {
    public var start: Position
    public var end: Position

    public init(start: Position, end: Position) {
        self.start = start
        self.end = end
    }
}

public struct TextDocumentIdentifier: Codable, Equatable, Sendable {
    public var uri: String

    public init(uri: String) {
        self.uri = uri
    }
}

public struct VersionedTextDocumentIdentifier: Codable, Equatable, Sendable {
    public var uri: String
    public var version: Int

    public init(uri: String, version: Int) {
        self.uri = uri
        self.version = version
    }
}

public struct TextDocumentItem: Codable, Sendable {
    public var uri: String
    public var languageId: String
    public var version: Int
    public var text: String

    public init(uri: String, languageId: String, version: Int, text: String) {
        self.uri = uri
        self.languageId = languageId
        self.version = version
        self.text = text
    }
}

public struct TextDocumentContentChangeEvent: Codable, Sendable {
    /// `nil` means the whole document changed.
    public var range: Range?
    public var text: String

    public init(range: Range? = nil, text: String) {
        self.range = range
        self.text = text
    }
}

// MARK: - Completion

public enum CompletionTriggerKind: Int, Codable, Sendable {
    case invoked = 1
    case triggerCharacter = 2
    case triggerForIncompleteCompletions = 3
}

public enum CompletionItemKind: Int, Codable, CaseIterable, Sendable {
    case text = 1
    case method = 2
    case function = 3
    case constructor = 4
    case field = 5
    case variable = 6
    case `class` = 7
    case interface = 8
    case module = 9
    case property = 10
    case unit = 11
    case value = 12
    case `enum` = 13
    case keyword = 14
    case snippet = 15
    case color = 16
    case file = 17
    case folder = 18
    case reference = 19
    case folderReference = 20
    case constant = 21
}

public struct MarkupContent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case plaintext
        case markdown
    }

    public var kind: Kind
    public var value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct CompletionItem: Codable, Identifiable, Sendable {
    public var label: String
    public var kind: CompletionItemKind?
    public var detail: String?
    public var documentation: MarkupContent?
    public var sortText: String?
    public var filterText: String?
    public var insertText: String?
    public var textEdit: TextEdit?

    public var id: String { label }

    /// Text actually inserted on completion.
    public var insertionText: String {
        if let textEdit {
            return textEdit.newText
        }
        return insertText ?? label
    }

    public init(
        label: String,
        kind: CompletionItemKind? = nil,
        detail: String? = nil,
        documentation: MarkupContent? = nil,
        sortText: String? = nil,
        filterText: String? = nil,
        insertText: String? = nil,
        textEdit: TextEdit? = nil
    ) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.documentation = documentation
        self.sortText = sortText
        self.filterText = filterText
        self.insertText = insertText
        self.textEdit = textEdit
    }
}

public struct TextEdit: Codable, Equatable, Sendable {
    public var range: Range
    public var newText: String

    public init(range: Range, newText: String) {
        self.range = range
        self.newText = newText
    }
}

/// Servers may answer with either a bare array or a `CompletionList`.
public struct CompletionList: Codable, Sendable {
    public var isIncomplete: Bool
    public var items: [CompletionItem]

    public init(isIncomplete: Bool, items: [CompletionItem]) {
        self.isIncomplete = isIncomplete
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode(CompletionList.self) {
            self = list
            return
        }
        self.init(isIncomplete: false, items: try decoder.singleValueContainer().decode([CompletionItem].self))
    }
}

// MARK: - Hover

public struct Hover: Codable, Equatable, Sendable {
    public var contents: MarkupContent
    public var range: Range?

    public init(contents: MarkupContent, range: Range? = nil) {
        self.contents = contents
        self.range = range
    }
}

// MARK: - Diagnostics

public enum DiagnosticSeverity: Int, Codable, CaseIterable, Sendable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

public enum DiagnosticCode: Codable, Equatable, Sendable {
    case integer(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

public struct Diagnostic: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(range.start.line):\(range.start.character):\(message)" }
    public var range: Range
    public var severity: DiagnosticSeverity?
    public var code: DiagnosticCode?
    public var source: String?
    public var message: String

    public init(
        range: Range,
        severity: DiagnosticSeverity? = nil,
        code: DiagnosticCode? = nil,
        source: String? = nil,
        message: String
    ) {
        self.range = range
        self.severity = severity
        self.code = code
        self.source = source
        self.message = message
    }
}

// MARK: - Symbols

public enum SymbolKind: Int, Codable, Sendable {
    case file = 1
    case module = 2
    case namespace = 3
    case package = 4
    case `class` = 5
    case method = 6
    case property = 7
    case field = 8
    case constructor = 9
    case `enum` = 10
    case interface = 11
    case function = 12
    case variable = 13
    case constant = 14
    case string = 15
    case array = 16
    case object = 17
    case key = 18
    case null_ = 19
    case boolean = 20
    case arrayElement = 21
}

public struct Location: Codable, Equatable, Sendable {
    public var uri: String
    public var range: Range

    public init(uri: String, range: Range) {
        self.uri = uri
        self.range = range
    }
}

public struct WorkspaceSymbol: Codable, Identifiable, Sendable {
    public var id: String { "\(name)-\(location.uri)" }
    public var name: String
    public var kind: SymbolKind
    public var location: Location

    public init(name: String, kind: SymbolKind, location: Location) {
        self.name = name
        self.kind = kind
        self.location = location
    }
}

// MARK: - Capabilities

public enum MarkupKind: String, Codable, Sendable {
    case plaintext
    case markdown
}

public struct CompletionOptions: Codable, Sendable {
    public var resolveProvider: Bool?
    public var triggerCharacters: [String]?

    public init(resolveProvider: Bool? = nil, triggerCharacters: [String]? = nil) {
        self.resolveProvider = resolveProvider
        self.triggerCharacters = triggerCharacters
    }
}

public struct ServerCapabilities: Codable, Sendable {
    public var textDocumentSync: Int?
    public var completionProvider: CompletionOptions?
    public var hoverProvider: Bool?
    public var signatureHelpProvider: [String]?
    public var referencesProvider: Bool?
    public var documentSymbolProvider: Bool?
    public var formattingProvider: Bool?
    public var definitionProvider: Bool?
    public var codeActionProvider: Bool?
    public var workspaceSymbolProvider: Bool?

    public init(
        textDocumentSync: Int? = nil,
        completionProvider: CompletionOptions? = nil,
        hoverProvider: Bool? = nil,
        signatureHelpProvider: [String]? = nil,
        referencesProvider: Bool? = nil,
        documentSymbolProvider: Bool? = nil,
        formattingProvider: Bool? = nil,
        definitionProvider: Bool? = nil,
        codeActionProvider: Bool? = nil,
        workspaceSymbolProvider: Bool? = nil
    ) {
        self.textDocumentSync = textDocumentSync
        self.completionProvider = completionProvider
        self.hoverProvider = hoverProvider
        self.signatureHelpProvider = signatureHelpProvider
        self.referencesProvider = referencesProvider
        self.documentSymbolProvider = documentSymbolProvider
        self.formattingProvider = formattingProvider
        self.definitionProvider = definitionProvider
        self.codeActionProvider = codeActionProvider
        self.workspaceSymbolProvider = workspaceSymbolProvider
    }

    public var supportsCompletion: Bool { completionProvider != nil }
    public var supportsHover: Bool { hoverProvider ?? false }
    public var supportsDefinition: Bool { definitionProvider ?? false }
    public var supportsFormatting: Bool { formattingProvider ?? false }
}

// MARK: - Requests

public struct InitializeParams: Encodable, Sendable {
    public var processId: Int?
    public var rootURI: String?
    public var capabilities: ClientCapabilities
    public var workspaceFolders: [WorkspaceFolder]?

    public init(
        processId: Int? = Int(ProcessInfo.processInfo.processIdentifier),
        rootURI: String? = nil,
        capabilities: ClientCapabilities = .default,
        workspaceFolders: [WorkspaceFolder]? = nil
    ) {
        self.processId = processId
        self.rootURI = rootURI
        self.capabilities = capabilities
        self.workspaceFolders = workspaceFolders
    }
}

public struct WorkspaceFolder: Encodable, Sendable {
    public var uri: String
    public var name: String

    public init(uri: String, name: String) {
        self.uri = uri
        self.name = name
    }
}

/// The capabilities this client advertises.
public struct ClientCapabilities: Encodable, Sendable {
    public struct TextDocument: Encodable, Sendable {
        public var synchronization: Synchronization
        public var completion: Completion
        public var hover: Hover
        public var definition: DynamicRegistration

        public init(
            synchronization: Synchronization = .init(),
            completion: Completion = .init(),
            hover: Hover = .init(),
            definition: DynamicRegistration = .init()
        ) {
            self.synchronization = synchronization
            self.completion = completion
            self.hover = hover
            self.definition = definition
        }
    }

    public struct DynamicRegistration: Encodable, Sendable {
        public var dynamicRegistration: Bool

        public init(dynamicRegistration: Bool = true) {
            self.dynamicRegistration = dynamicRegistration
        }
    }

    public struct Synchronization: Encodable, Sendable {
        public var dynamicRegistration: Bool
        public var willSave: Bool
        public var didSave: Bool

        public init(dynamicRegistration: Bool = true, willSave: Bool = true, didSave: Bool = true) {
            self.dynamicRegistration = dynamicRegistration
            self.willSave = willSave
            self.didSave = didSave
        }
    }

    public struct Completion: Encodable, Sendable {
        public struct Item: Encodable, Sendable {
            public var snippetSupport: Bool
            public var documentationFormat: [MarkupKind]

            public init(snippetSupport: Bool = false, documentationFormat: [MarkupKind] = [.plaintext]) {
                self.snippetSupport = snippetSupport
                self.documentationFormat = documentationFormat
            }
        }

        public var dynamicRegistration: Bool
        public var completionItem: Item

        public init(dynamicRegistration: Bool = true, completionItem: Item = .init()) {
            self.dynamicRegistration = dynamicRegistration
            self.completionItem = completionItem
        }
    }

    public struct Hover: Encodable, Sendable {
        public var dynamicRegistration: Bool
        public var contentFormat: [MarkupKind]

        public init(dynamicRegistration: Bool = true, contentFormat: [MarkupKind] = [.plaintext, .markdown]) {
            self.dynamicRegistration = dynamicRegistration
            self.contentFormat = contentFormat
        }
    }

    public struct Workspace: Encodable, Sendable {
        public var symbol: DynamicRegistration
        public var workspaceFolders: Bool

        public init(symbol: DynamicRegistration = .init(), workspaceFolders: Bool = true) {
            self.symbol = symbol
            self.workspaceFolders = workspaceFolders
        }
    }

    public var textDocument: TextDocument
    public var workspace: Workspace

    public init(textDocument: TextDocument = .init(), workspace: Workspace = .init()) {
        self.textDocument = textDocument
        self.workspace = workspace
    }

    public static let `default` = ClientCapabilities()
}

public struct InitializeResult: Decodable, Sendable {
    public var capabilities: ServerCapabilities

    public init(capabilities: ServerCapabilities) {
        self.capabilities = capabilities
    }
}

// MARK: - Message envelopes

struct LSPRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: AnyEncodable?
}

struct LSPNotification: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: AnyEncodable?
}

/// Type-erasing box so `params` can hold any encodable payload.
struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

/// Anything the transport can decode, to route responses and notifications.
struct RawMessage: Decodable {
    let id: Int?
    let method: String?
    let result: JSONValue?
    let error: ResponseError?

    struct ResponseError: Decodable, Error {
        let code: Int
        let message: String

        var localizedDescription: String { "LSP error \(code): \(message)" }
    }

    private enum CodingKeys: String, CodingKey {
        case id, method, result, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        error = try container.decodeIfPresent(ResponseError.self, forKey: .error)
    }
}

/// Minimal JSON tree so message bodies can be re-decoded into concrete types.
public enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public func decode<T: Decodable>(as type: T.Type, using decoder: JSONDecoder) throws -> T {
        try decoder.decode(T.self, from: JSONEncoder().encode(self))
    }
}