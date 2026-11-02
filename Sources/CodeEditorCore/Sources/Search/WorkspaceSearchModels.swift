import Foundation

// MARK: - WorkspaceSearchOptions

/// Configuration for project-wide text search and replace.
public struct WorkspaceSearchOptions: Equatable, Sendable {
    public var query: String
    public var replacement: String
    public var isCaseSensitive: Bool
    public var isWholeWord: Bool
    public var isRegex: Bool
    public var filePattern: String

    public init(
        query: String = "",
        replacement: String = "",
        isCaseSensitive: Bool = false,
        isWholeWord: Bool = false,
        isRegex: Bool = false,
        filePattern: String = ""
    ) {
        self.query = query
        self.replacement = replacement
        self.isCaseSensitive = isCaseSensitive
        self.isWholeWord = isWholeWord
        self.isRegex = isRegex
        self.filePattern = filePattern
    }
}

// MARK: - OpenDocumentSnapshot

/// An immutable point-in-time snapshot of an in-memory document for background searches.
public struct OpenDocumentSnapshot: Sendable, Equatable {
    public let url: URL
    public let content: String

    public init(url: URL, content: String) {
        self.url = url
        self.content = content
    }
}

// MARK: - WorkspaceSearchMatch

/// A single matched occurrence of a search query in a workspace file.
public struct WorkspaceSearchMatch: Identifiable, Equatable, Sendable {
    public let id: String
    public let fileURL: URL
    public let relativePath: String
    /// 1-indexed line number in the source file.
    public let lineNumber: Int
    /// 1-indexed character column on the line.
    public let column: Int
    /// The UTF-16 character range within `lineContent` corresponding to the match.
    public let matchRangeInLine: NSRange
    /// The line snippet text containing the match, trimmed of trailing newline.
    public let lineContent: String
    /// The exact text substring that matched the query.
    public let matchedText: String

    public init(
        id: String? = nil,
        fileURL: URL,
        relativePath: String,
        lineNumber: Int,
        column: Int,
        matchRangeInLine: NSRange,
        lineContent: String,
        matchedText: String
    ) {
        self.id = id ?? "\(fileURL.path):\(lineNumber):\(column):\(matchedText.count)"
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.lineNumber = lineNumber
        self.column = column
        self.matchRangeInLine = matchRangeInLine
        self.lineContent = lineContent
        self.matchedText = matchedText
    }
}

// MARK: - WorkspaceSearchFileResult

/// Grouped search matches for a single file in the workspace.
public struct WorkspaceSearchFileResult: Identifiable, Equatable, Sendable {
    public var id: String { fileURL.standardizedFileURL.path }
    public let fileURL: URL
    public let relativePath: String
    public var matches: [WorkspaceSearchMatch]

    public var matchCount: Int { matches.count }

    public init(fileURL: URL, relativePath: String, matches: [WorkspaceSearchMatch]) {
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.matches = matches
    }
}

// MARK: - WorkspaceSearchError

public enum WorkspaceSearchError: Error, LocalizedError, Equatable, Sendable {
    case invalidRegex(String)
    case fileReadFailed(String)
    case fileWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRegex(let msg): return "Invalid regular expression: \(msg)"
        case .fileReadFailed(let msg): return "Failed to read file: \(msg)"
        case .fileWriteFailed(let msg): return "Failed to write file: \(msg)"
        }
    }
}
