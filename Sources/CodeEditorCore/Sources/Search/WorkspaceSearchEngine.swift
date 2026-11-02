import Darwin
import Foundation

/// Fast, bounded workspace-wide search and replace engine.
///
/// Features:
/// - Case-sensitive, whole-word, and regular expression searching.
/// - Plain-text and regex template replacement (with capture groups `$1`, `$2`).
/// - File filtering (e.g. `*.swift, *.go`).
/// - Binary file skipping and directory pruning (`.git`, `.build`, `node_modules`).
/// - Live in-memory search & replacement for active uncommitted documents.
/// - Atomic file writes for on-disk replacements.
public enum WorkspaceSearchEngine {

    public nonisolated static let skippedDirectories: Set<String> = [
        ".git", ".build", "build", "node_modules", "DerivedData", ".swiftpm", "Pods",
        ".xcodeproj", ".xcworkspace", ".framework", ".bundle",
    ]

    public nonisolated static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "ico", "icns", "pdf", "zip", "tar", "gz", "tgz",
        "o", "a", "dylib", "so", "bin", "exe", "car", "nib", "storyboardc", "ds_store",
    ]

    // MARK: - Filter Matching

    /// Evaluates whether a file matches comma/semicolon-separated glob filters.
    public static func matchesFilter(relativePath: String, filename: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let filters = trimmed.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if filters.isEmpty { return true }

        for filter in filters {
            if filter.hasPrefix("*.") {
                let ext = String(filter.dropFirst(2))
                if filename.caseInsensitiveCompare(ext) == .orderedSame
                    || (filename as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame
                {
                    return true
                }
            }
            if Darwin.fnmatch(filter, relativePath, FNM_CASEFOLD) == 0
                || Darwin.fnmatch(filter, filename, FNM_CASEFOLD) == 0
            {
                return true
            }
        }
        return false
    }

    /// Fast binary check looking for null bytes in the first 8 KB.
    public static func isBinaryData(_ data: Data) -> Bool {
        let scanLength = min(data.count, 8192)
        guard scanLength > 0 else { return false }
        return data.prefix(scanLength).contains(0)
    }

    // MARK: - Regex Compilation

    /// Constructs an `NSRegularExpression` matching the specified search options.
    public static func makeRegex(options: WorkspaceSearchOptions) throws -> NSRegularExpression {
        guard !options.query.isEmpty else {
            throw WorkspaceSearchError.invalidRegex("Search query is empty")
        }

        let pattern: String
        if options.isRegex {
            pattern = options.isWholeWord ? "\\b(?:\(options.query))\\b" : options.query
        } else {
            let escaped = NSRegularExpression.escapedPattern(for: options.query)
            pattern = options.isWholeWord ? "\\b\(escaped)\\b" : escaped
        }

        let regexOptions: NSRegularExpression.Options = options.isCaseSensitive ? [] : [.caseInsensitive]
        do {
            return try NSRegularExpression(pattern: pattern, options: regexOptions)
        } catch {
            throw WorkspaceSearchError.invalidRegex(error.localizedDescription)
        }
    }

    // MARK: - Content Search

    /// Searches text content and returns all match positions, line numbers, and snippets.
    public static func searchContent(
        _ content: String,
        fileURL: URL,
        relativePath: String,
        options: WorkspaceSearchOptions
    ) throws -> [WorkspaceSearchMatch] {
        guard !options.query.isEmpty else { return [] }

        let regex = try makeRegex(options: options)
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = regex.matches(in: content, options: [], range: fullRange)
        guard !matches.isEmpty else { return [] }

        // Precompute line starts for fast line number resolution
        var lineStarts: [Int] = [0]
        let length = nsContent.length
        var index = 0
        while index < length {
            if nsContent.character(at: index) == 10 {  // '\n'
                lineStarts.append(index + 1)
            }
            index += 1
        }

        var results: [WorkspaceSearchMatch] = []
        results.reserveCapacity(matches.count)

        for match in matches {
            let matchRange = match.range
            guard matchRange.location != NSNotFound else { continue }

            let lineIndex = binarySearchLineStarts(lineStarts, target: matchRange.location)
            let lineNumber = lineIndex + 1
            let lineStart = lineStarts[lineIndex]
            let column = matchRange.location - lineStart + 1

            let lineRange = nsContent.lineRange(for: matchRange)
            let rawLine = nsContent.substring(with: lineRange)
            let lineContent = rawLine.trimmingCharacters(in: .newlines)
            let matchOffsetInLine = matchRange.location - lineRange.location
            let rangeInLine = NSRange(location: max(0, matchOffsetInLine), length: matchRange.length)

            let matchedText = nsContent.substring(with: matchRange)

            results.append(
                WorkspaceSearchMatch(
                    fileURL: fileURL,
                    relativePath: relativePath,
                    lineNumber: lineNumber,
                    column: max(1, column),
                    matchRangeInLine: rangeInLine,
                    lineContent: lineContent,
                    matchedText: matchedText
                ))
        }

        return results
    }

    private static func binarySearchLineStarts(_ starts: [Int], target: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        var result = 0
        while low <= high {
            let mid = low + (high - low) / 2
            if starts[mid] <= target {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    // MARK: - Workspace Directory Search

    /// Asynchronously walks the workspace directory and searches files matching options.
    public static func search(
        root: URL,
        options: WorkspaceSearchOptions,
        openSnapshots: [OpenDocumentSnapshot] = [],
        maxMatches: Int = 5000,
        maxFileSize: Int = 5 * 1024 * 1024
    ) async throws -> [WorkspaceSearchFileResult] {
        guard !options.query.isEmpty else { return [] }

        // Test regex validity before starting directory traversal
        _ = try makeRegex(options: options)

        let standardizedRoot = root.standardizedFileURL
        let rootPath = standardizedRoot.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        var fileResults: [WorkspaceSearchFileResult] = []
        var totalMatchCount = 0

        guard
            let enumerator = FileManager.default.enumerator(
                at: standardizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsPackageDescendants]
            )
        else {
            return []
        }

        while let item = enumerator.nextObject() as? URL {
            try Task.checkCancellation()

            let filename = item.lastPathComponent
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                if skippedDirectories.contains(filename) || filename.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
                continue
            }

            if filename.hasPrefix(".") { continue }
            let ext = item.pathExtension.lowercased()
            if binaryExtensions.contains(ext) { continue }

            let itemPath = item.standardizedFileURL.path
            let relativePath =
                itemPath.hasPrefix(rootPrefix)
                ? String(itemPath.dropFirst(rootPrefix.count))
                : filename

            guard matchesFilter(relativePath: relativePath, filename: filename, pattern: options.filePattern) else {
                continue
            }

            // In-memory document content takes priority over on-disk content
            let contentToSearch: String?
            if let openSnap = openSnapshots.first(where: {
                $0.url.standardizedFileURL.path == itemPath
            }) {
                contentToSearch = openSnap.content
            } else {
                if let size = resourceValues?.fileSize, size > maxFileSize {
                    continue
                }
                guard let data = try? Data(contentsOf: item, options: [.mappedIfSafe]),
                    !isBinaryData(data),
                    let decoded = String(data: data, encoding: .utf8)
                else {
                    continue
                }
                contentToSearch = decoded
            }

            guard let content = contentToSearch else { continue }
            let matches = try searchContent(content, fileURL: item, relativePath: relativePath, options: options)

            if !matches.isEmpty {
                fileResults.append(
                    WorkspaceSearchFileResult(
                        fileURL: item,
                        relativePath: relativePath,
                        matches: matches
                    ))
                totalMatchCount += matches.count
                if totalMatchCount >= maxMatches {
                    break
                }
            }
        }

        fileResults.sort { $0.relativePath < $1.relativePath }
        return fileResults
    }

    /// Convenience wrapper taking live MainActor Document instances and snapshotting them.
    @MainActor
    public static func search(
        root: URL,
        options: WorkspaceSearchOptions,
        openDocuments: [Document],
        maxMatches: Int = 5000,
        maxFileSize: Int = 5 * 1024 * 1024
    ) async throws -> [WorkspaceSearchFileResult] {
        let snapshots = openDocuments.compactMap { doc -> OpenDocumentSnapshot? in
            guard let url = doc.url else { return nil }
            return OpenDocumentSnapshot(url: url, content: doc.content)
        }
        return try await search(
            root: root,
            options: options,
            openSnapshots: snapshots,
            maxMatches: maxMatches,
            maxFileSize: maxFileSize
        )
    }

    // MARK: - Replace Operations

    /// Replaces occurrences in a content string according to the given options.
    public static func replaceInString(
        _ content: String,
        options: WorkspaceSearchOptions
    ) throws -> (newContent: String, count: Int) {
        guard !options.query.isEmpty else { return (content, 0) }

        let regex = try makeRegex(options: options)
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let count = regex.numberOfMatches(in: content, options: [], range: fullRange)
        guard count > 0 else { return (content, 0) }

        let template =
            options.isRegex
            ? options.replacement
            : NSRegularExpression.escapedTemplate(for: options.replacement)

        let replaced = regex.stringByReplacingMatches(
            in: content,
            options: [],
            range: fullRange,
            withTemplate: template
        )
        return (replaced, count)
    }

    /// Replaces all occurrences across matched files, updating open documents in memory
    /// and saving un-opened files atomically to disk.
    @MainActor
    @discardableResult
    public static func replaceAll(
        files: [WorkspaceSearchFileResult],
        replacement: String,
        options: WorkspaceSearchOptions,
        openDocuments: [Document] = []
    ) throws -> Int {
        var effectiveOptions = options
        effectiveOptions.replacement = replacement
        var totalReplaced = 0

        for file in files {
            if let openDoc = openDocuments.first(where: {
                $0.url?.standardizedFileURL.path == file.fileURL.standardizedFileURL.path
            }) {
                let (newContent, count) = try replaceInString(openDoc.content, options: effectiveOptions)
                if count > 0 {
                    openDoc.setContent(newContent)
                    totalReplaced += count
                }
            } else {
                guard let data = try? Data(contentsOf: file.fileURL),
                    let content = String(data: data, encoding: .utf8)
                else { continue }

                let (newContent, count) = try replaceInString(content, options: effectiveOptions)
                if count > 0 {
                    guard let outData = newContent.data(using: .utf8) else { continue }
                    do {
                        try outData.write(to: file.fileURL, options: .atomic)
                        totalReplaced += count
                    } catch {
                        throw WorkspaceSearchError.fileWriteFailed(
                            "Could not write to \(file.relativePath): \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
        return totalReplaced
    }

    /// Replaces a single matched occurrence in an open document or file on disk.
    @MainActor
    public static func replaceMatch(
        _ match: WorkspaceSearchMatch,
        replacement: String,
        openDocument: Document?
    ) throws {
        if let doc = openDocument {
            let lines = doc.content.components(separatedBy: "\n")
            guard match.lineNumber >= 1 && match.lineNumber <= lines.count else { return }
            let lineIndex = match.lineNumber - 1
            let targetLine = lines[lineIndex] as NSString
            guard match.matchRangeInLine.location + match.matchRangeInLine.length <= targetLine.length else { return }

            let replacedLine = targetLine.replacingCharacters(in: match.matchRangeInLine, with: replacement)
            var newLines = lines
            newLines[lineIndex] = replacedLine
            doc.setContent(newLines.joined(separator: "\n"))
        } else {
            guard let data = try? Data(contentsOf: match.fileURL),
                let content = String(data: data, encoding: .utf8)
            else {
                throw WorkspaceSearchError.fileReadFailed("Could not read \(match.relativePath)")
            }

            let lines = content.components(separatedBy: "\n")
            guard match.lineNumber >= 1 && match.lineNumber <= lines.count else { return }
            let lineIndex = match.lineNumber - 1
            let targetLine = lines[lineIndex] as NSString
            guard match.matchRangeInLine.location + match.matchRangeInLine.length <= targetLine.length else { return }

            let replacedLine = targetLine.replacingCharacters(in: match.matchRangeInLine, with: replacement)
            var newLines = lines
            newLines[lineIndex] = replacedLine
            let newContent = newLines.joined(separator: "\n")
            guard let outData = newContent.data(using: .utf8) else { return }
            try outData.write(to: match.fileURL, options: .atomic)
        }
    }
}
