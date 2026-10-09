import Foundation

// MARK: - Language

/// A document language, resolved from a file's extension or set by the user.
public struct Language: Sendable, Equatable, Hashable {
    public let identifier: String
    public let displayName: String
    public let fileExtensions: [String]
    public let lineEnding: LineEnding

    public init(
        identifier: String,
        displayName: String,
        fileExtensions: [String] = [],
        lineEnding: LineEnding = .lf
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.fileExtensions = fileExtensions
        self.lineEnding = lineEnding
    }
}

/// Standard document languages.
public extension Language {
    static let swift = Language(identifier: "swift", displayName: "Swift", fileExtensions: ["swift"])
    static let javascript = Language(identifier: "javascript", displayName: "JavaScript", fileExtensions: ["js", "jsx", "mjs", "cjs"])
    static let typescript = Language(identifier: "typescript", displayName: "TypeScript", fileExtensions: ["ts", "tsx"])
    static let python = Language(identifier: "python", displayName: "Python", fileExtensions: ["py"])
    static let json = Language(identifier: "json", displayName: "JSON", fileExtensions: ["json"])
    static let markdown = Language(identifier: "markdown", displayName: "Markdown", fileExtensions: ["md", "markdown"])
    static let html = Language(identifier: "html", displayName: "HTML", fileExtensions: ["html", "htm"])
    static let css = Language(identifier: "css", displayName: "CSS", fileExtensions: ["css", "scss", "sass"])
    static let shell = Language(identifier: "shell", displayName: "Shell", fileExtensions: ["sh", "bash", "zsh"])
    static let yaml = Language(identifier: "yaml", displayName: "YAML", fileExtensions: ["yml", "yaml"])
    static let toml = Language(identifier: "toml", displayName: "TOML", fileExtensions: ["toml"])
    static let text = Language(identifier: "plaintext", displayName: "Plain Text", fileExtensions: ["txt"])
    static let unknown = Language(identifier: "plaintext", displayName: "Plain Text")
}

// MARK: - LineEnding

/// Line ending style.
public enum LineEnding: String, CaseIterable, Codable, Sendable {
    case cr = "\r"
    case lf = "\n"
    case crlf = "\r\n"

    public var character: String { rawValue }

    /// Detect line ending from text (prefer CRLF > LF > CR).
    public static func detect(from text: String) -> LineEnding {
        if text.contains("\r\n") { return .crlf }
        if text.contains("\r") { return .cr }
        return .lf
    }
}

// MARK: - TextSelection

/// A selection expressed as UTF-8 offsets into the document content.
public struct TextSelection: Equatable, Hashable, Codable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public init(location: Int = 0, length: Int = 0) {
        self.start = location
        self.end = location + length
    }

    public var location: Int { start }
    public var length: Int { end - start }
    public var isEmpty: Bool { start == end }

    public var nsRange: NSRange {
        NSRange(location: start, length: end - start)
    }
}

// MARK: - Document

/// Protocol for document-related notifications.
public protocol DocumentDelegate: AnyObject {
    func documentDidModify(_ document: Document)
    func documentDidSave(_ document: Document)
    func documentDidClose(_ document: Document)
    func documentDidChangeLanguage(_ document: Document, to language: Language)
    func documentDidChangeLineEnding(_ document: Document, to lineEnding: LineEnding)
}

/// A single open document.
@MainActor
@Observable
public final class Document: Identifiable {
    /// Unique identifier for this document.
    public let id: UUID

    /// The file URL this document represents (nil for untitled documents).
    public private(set) var url: URL?

    /// The current content.
    public private(set) var content: String

    /// Content split into lines, cached for fast offset math.
    public private(set) var lines: [String] = []

    /// The current language.
    public private(set) var language: Language

    /// The current line ending.
    public private(set) var lineEnding: LineEnding

    /// Whether the document has unsaved changes.
    public private(set) var isModified: Bool = false

    /// Read-only flag.
    public private(set) var isReadOnly: Bool = false

    /// The primary selection.
    public private(set) var selection: TextSelection = TextSelection()

    /// All selections (for multi-cursor).
    public private(set) var selections: [TextSelection] = []

    /// The delegate receiving document events.
    public weak var delegate: DocumentDelegate?

    /// Undo manager for the document. The text view supplies its own `CEUndoManager` so the
    /// editor's typing history and the document's programmatic edits share one stack.
    public let undoManager: UndoManager?

    // MARK: - Computed

    public var name: String {
        url?.lastPathComponent ?? "Untitled"
    }

    public var title: String {
        isModified ? "\(name) *" : name
    }

    public var isUntitled: Bool { url == nil }

    public var absolutePath: String? { url?.path }

    public var lineCount: Int { lines.count }

    /// Number of UTF-8 bytes in the content.
    public var characterCount: Int { content.utf8.count }

    /// Line/column of the primary selection's start.
    public var selectionLine: Int { lineAndColumn(for: selection.start)?.line ?? 0 }

    public var selectionColumn: Int { lineAndColumn(for: selection.start)?.column ?? 0 }

    // MARK: - Initialization

    public init(
        content: String = "",
        language: Language = .text,
        lineEnding: LineEnding? = nil,
        url: URL? = nil,
        undoManager: UndoManager? = UndoManager()
    ) {
        self.id = UUID()
        self.content = content
        self.language = language
        self.lineEnding = lineEnding ?? .detect(from: content)
        self.url = url
        self.undoManager = undoManager
        self.lines = Self.split(content, by: self.lineEnding)
    }

    /// Create an untitled document with the given language.
    public static func untitled(language: Language = .text) -> Document {
        Document(content: "", language: language)
    }

    /// Load a document from disk.
    public static func load(from url: URL) async throws -> Document {
        let data: Data
        do {
            data = try await Task.detached { try Data(contentsOf: url) }.value
        } catch {
            throw DocumentError.failedToRead(url, error.localizedDescription)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw DocumentError.failedToConvertToUTF8(url, "UTF-8")
        }

        return Document(
            content: content,
            language: language(for: url),
            lineEnding: .detect(from: content),
            url: url
        )
    }

    /// Resolve a language from a file extension.
    public static func language(for url: URL) -> Language {
        let ext = url.pathExtension.lowercased()
        let all: [Language] = [
            .swift, .javascript, .typescript, .python, .json, .markdown,
            .html, .css, .shell, .yaml, .toml, .text
        ]
        return all.first { $0.fileExtensions.contains(ext) } ?? .unknown
    }

    private static func split(_ content: String, by lineEnding: LineEnding) -> [String] {
        var lines = content.components(separatedBy: lineEnding.character)
        if content.hasSuffix(lineEnding.character) {
            lines.removeLast()
        }
        return lines
    }

    // MARK: - Content mutation

    /// Replace the whole content. Used by the text view's two-way binding.
    public func setContent(_ newContent: String) {
        guard newContent != content else { return }
        let previous = content
        apply(newContent)
        recordUndo(previous)
    }

    /// Insert `text` at the primary selection, replacing the selected range.
    public func insert(_ text: String) {
        let range = selection.nsRange
        let previous = content
        let replacement = (content as NSString).replacingCharacters(in: range, with: text)
        apply(replacement)
        setSelection(location: selection.start + text.utf8.count)
        recordUndo(previous)
    }

    /// Delete the primary selection.
    public func deleteSelection() {
        guard !selection.isEmpty else { return }
        let previous = content
        apply((content as NSString).replacingCharacters(in: selection.nsRange, with: ""))
        setSelection(location: selection.start)
        recordUndo(previous)
    }

    private func apply(_ newContent: String) {
        content = newContent
        lines = Self.split(newContent, by: lineEnding)
        isModified = true
        delegate?.documentDidModify(self)
    }

    private func recordUndo(_ previousContent: String) {
        undoManager?.registerUndo(withTarget: self) { document in
            document.apply(previousContent)
        }
    }

    // MARK: - Offset math

    /// UTF-8 offset of a line/column pair.
    public func offset(forLine line: Int, column: Int) -> Int? {
        guard line >= 0, line < lines.count, column >= 0 else { return nil }
        var offset = 0
        for index in 0..<line {
            offset += lines[index].utf8.count + lineEnding.character.utf8.count
        }
        offset += lines[line].utf8.prefix(column).count
        return offset
    }

    /// Line/column pair for a UTF-8 offset.
    public func lineAndColumn(for offset: Int) -> (line: Int, column: Int)? {
        guard offset >= 0, offset <= content.utf8.count else { return nil }

        var lineOffset = 0
        for (index, text) in lines.enumerated() {
            if offset <= lineOffset + text.utf8.count {
                return (index, offset - lineOffset)
            }
            lineOffset += text.utf8.count + lineEnding.character.utf8.count
        }

        let last = max(0, lines.count - 1)
        return (last, lines.isEmpty ? 0 : lines[last].utf8.count)
    }

    /// An `NSRange` for a UTF-8 offset range.
    public func nsRange(from start: Int, to end: Int) -> NSRange? {
        guard start >= 0, end >= start, end <= content.utf8.count else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The substring covered by the primary selection.
    public var selectedText: String {
        let range = nsRange(from: selection.start, to: selection.end) ?? NSRange(location: 0, length: 0)
        return (content as NSString).substring(with: range)
    }

    /// Text of a single 0-indexed line.
    public func line(_ line: Int) -> String? {
        guard line >= 0, line < lines.count else { return nil }
        return lines[line]
    }

    /// Byte range covering the given whole lines, including their trailing newlines.
    public func range(ofLines from: Int, to: Int) -> NSRange? {
        guard let start = offset(forLine: max(0, from), column: 0) else { return nil }
        let lastLine = min(to, lines.count - 1)
        guard lastLine >= 0 else { return nil }
        let end: Int
        if lastLine == lines.count - 1 {
            end = content.utf8.count
        } else {
            end = offset(forLine: lastLine + 1, column: 0) ?? content.utf8.count
        }
        return NSRange(location: start, length: end - start)
    }

    // MARK: - Selection

    public func setSelection(location: Int) {
        let clamped = min(max(0, location), content.utf8.count)
        selection = TextSelection(location: clamped)
        selections = [selection]
    }

    public func setSelection(from: Int, to: Int) {
        let clampedStart = min(max(0, from), content.utf8.count)
        let clampedEnd = min(max(0, to), content.utf8.count)
        selection = TextSelection(start: clampedStart, end: clampedEnd)
        selections = [selection]
    }

    public func setSelection(_ newSelection: TextSelection) {
        setSelection(from: newSelection.start, to: newSelection.end)
    }

    public func clearSelections() {
        setSelection(location: selection.start)
    }

    public func addSelection(_ newSelection: TextSelection) {
        selections.append(newSelection)
    }

    public func selectAll() {
        setSelection(from: 0, to: content.utf8.count)
    }

    /// Select the line containing `offset`.
    public func selectLine(containing offset: Int) {
        guard let position = lineAndColumn(for: offset),
              let range = range(ofLines: position.line, to: position.line) else { return }
        setSelection(from: range.location, to: range.location + range.length)
    }

    // MARK: - Language & line endings

    public func setLanguage(_ language: Language) {
        guard language != self.language else { return }
        self.language = language
        delegate?.documentDidChangeLanguage(self, to: language)
    }

    /// Switch the document's line ending, normalizing the content to match.
    public func setLineEnding(_ newLineEnding: LineEnding) {
        guard newLineEnding != lineEnding else { return }
        let previous = content
        let normalized = content.replacingOccurrences(of: lineEnding.character, with: newLineEnding.character)
        lineEnding = newLineEnding
        delegate?.documentDidChangeLineEnding(self, to: newLineEnding)
        apply(normalized)
        recordUndo(previous)
    }

    // MARK: - Persistence

    public func save() async throws {
        guard let url else { throw DocumentError.noURL }
        let data = Data(content.utf8)
        do {
            try await Task.detached { try data.write(to: url) }.value
        } catch {
            throw DocumentError.failedToWrite(url, error.localizedDescription)
        }
        isModified = false
        delegate?.documentDidSave(self)
    }

    public func save(to newURL: URL) async throws {
        url = newURL
        try await save()
    }

    public func close() {
        delegate?.documentDidClose(self)
    }
}

// MARK: - Errors

public enum DocumentError: LocalizedError, Equatable {
    case noURL
    case failedToRead(URL, String)
    case failedToWrite(URL, String)
    case failedToConvertToUTF8(URL, String)

    public var errorDescription: String? {
        switch self {
        case .noURL:
            "This document has no file location yet."
        case .failedToRead(let url, let reason):
            "Could not read \(url.lastPathComponent): \(reason)"
        case .failedToWrite(let url, let reason):
            "Could not save \(url.lastPathComponent): \(reason)"
        case .failedToConvertToUTF8(let url, let encoding):
            "\(url.lastPathComponent) is not valid \(encoding) text."
        }
    }
}

// MARK: - DocumentManager

public protocol DocumentManagerDelegate: AnyObject {
    func didOpenDocument(_ document: Document)
    func didCloseDocument(_ document: Document)
}

/// Owns the set of open documents.
@MainActor
@Observable
public final class DocumentManager {
    public private(set) var documents: [Document] = []
    public private(set) var activeDocument: Document?

    public weak var delegate: DocumentManagerDelegate?

    public init() {}

    // MARK: - Queries

    public var openCount: Int { documents.count }

    public var hasModifiedDocuments: Bool { documents.contains { $0.isModified } }

    public func isDocumentOpen(at url: URL) -> Bool {
        documents.contains { $0.url == url }
    }

    public func existingDocument(at url: URL) -> Document? {
        documents.first { $0.url == url }
    }

    // MARK: - Opening and closing

    /// Open the file, or focus it if it is already open.
    @discardableResult
    public func open(_ url: URL) async throws -> Document {
        if let existing = existingDocument(at: url) {
            activeDocument = existing
            return existing
        }
        let loaded = try await Document.load(from: url)
        add(loaded)
        return loaded
    }

    @discardableResult
    public func open(_ document: Document) -> Document {
        if let url = document.url, let existing = existingDocument(at: url) {
            activeDocument = existing
            return existing
        }
        add(document)
        return document
    }

    public func activate(_ document: Document) {
        guard documents.contains(where: { $0 === document }) else { return }
        activeDocument = document
    }

    public func close(_ document: Document) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        if activeDocument === document {
            let next = index < documents.count ? documents[index] : documents.last
            activeDocument = next
        }
        document.delegate = nil
        document.close()
        delegate?.didCloseDocument(document)
    }

    public func closeAll() {
        for document in documents {
            document.delegate = nil
            document.close()
        }
        documents.removeAll()
        activeDocument = nil
    }

    public func saveAll() async {
        for document in documents where document.isModified {
            try? await document.save()
        }
    }

    private func add(_ document: Document) {
        document.delegate = self
        documents.append(document)
        activeDocument = document
        delegate?.didOpenDocument(document)
    }
}

// MARK: - DocumentManager + DocumentDelegate

extension DocumentManager: DocumentDelegate {
    public func documentDidModify(_ document: Document) {}

    public func documentDidSave(_ document: Document) {
        delegate?.didOpenDocument(document)
    }

    public func documentDidClose(_ document: Document) {}

    public func documentDidChangeLanguage(_ document: Document, to language: Language) {}

    public func documentDidChangeLineEnding(_ document: Document, to lineEnding: LineEnding) {}
}