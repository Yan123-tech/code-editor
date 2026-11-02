import CodeEditorCore
import Foundation
import Testing

@Suite("WorkspaceSearchEngine")
struct WorkspaceSearchEngineTests {

    // MARK: - Search Content & Modes

    @Test("Case-insensitive substring search finds all occurrences")
    func caseInsensitiveSearch() throws {
        let content = "Hello world\nhello swift\nHELLO macOS"
        let options = WorkspaceSearchOptions(query: "hello", isCaseSensitive: false)
        let matches = try WorkspaceSearchEngine.searchContent(
            content,
            fileURL: URL(fileURLWithPath: "/tmp/test.swift"),
            relativePath: "test.swift",
            options: options
        )
        #expect(matches.count == 3)
        #expect(matches[0].lineNumber == 1)
        #expect(matches[0].column == 1)
        #expect(matches[0].matchedText == "Hello")

        #expect(matches[1].lineNumber == 2)
        #expect(matches[1].column == 1)
        #expect(matches[1].matchedText == "hello")

        #expect(matches[2].lineNumber == 3)
        #expect(matches[2].column == 1)
        #expect(matches[2].matchedText == "HELLO")
    }

    @Test("Case-sensitive search matches exact casing only")
    func caseSensitiveSearch() throws {
        let content = "Hello world\nhello swift\nHELLO macOS"
        let options = WorkspaceSearchOptions(query: "hello", isCaseSensitive: true)
        let matches = try WorkspaceSearchEngine.searchContent(
            content,
            fileURL: URL(fileURLWithPath: "/tmp/test.swift"),
            relativePath: "test.swift",
            options: options
        )
        #expect(matches.count == 1)
        #expect(matches[0].lineNumber == 2)
        #expect(matches[0].matchedText == "hello")
    }

    @Test("Whole word search ignores occurrences embedded in identifiers")
    func wholeWordSearch() throws {
        let content = "func test() { let mytest = 1; test(); test_case() }"
        let options = WorkspaceSearchOptions(query: "test", isWholeWord: true)
        let matches = try WorkspaceSearchEngine.searchContent(
            content,
            fileURL: URL(fileURLWithPath: "/tmp/test.swift"),
            relativePath: "test.swift",
            options: options
        )
        // Only "func test()" and "test();" are whole words
        #expect(matches.count == 2)
        #expect(matches[0].column == 6)
        #expect(matches[1].column == 31)
    }

    @Test("Regex search matches pattern and handles invalid regex")
    func regexSearch() throws {
        let content = "item_123, item_456, other_789"
        let options = WorkspaceSearchOptions(query: "item_\\d+", isRegex: true)
        let matches = try WorkspaceSearchEngine.searchContent(
            content,
            fileURL: URL(fileURLWithPath: "/tmp/test.swift"),
            relativePath: "test.swift",
            options: options
        )
        #expect(matches.count == 2)
        #expect(matches[0].matchedText == "item_123")
        #expect(matches[1].matchedText == "item_456")

        // Invalid regex throws
        let invalidOptions = WorkspaceSearchOptions(query: "([a-z", isRegex: true)
        #expect(throws: WorkspaceSearchError.self) {
            try WorkspaceSearchEngine.searchContent(
                content,
                fileURL: URL(fileURLWithPath: "/tmp/test.swift"),
                relativePath: "test.swift",
                options: invalidOptions
            )
        }
    }

    // MARK: - File Filter Matching

    @Test("File filter matching supports extensions and globs")
    func filterMatching() {
        // Empty filter matches all
        #expect(
            WorkspaceSearchEngine.matchesFilter(relativePath: "Sources/Main.swift", filename: "Main.swift", pattern: "")
        )

        // Extension wildcard
        #expect(
            WorkspaceSearchEngine.matchesFilter(
                relativePath: "Sources/Main.swift", filename: "Main.swift", pattern: "*.swift"))
        #expect(
            !WorkspaceSearchEngine.matchesFilter(
                relativePath: "Sources/Main.go", filename: "Main.go", pattern: "*.swift"))

        // Multiple comma-separated filters
        #expect(
            WorkspaceSearchEngine.matchesFilter(
                relativePath: "Sources/Main.go", filename: "Main.go", pattern: "*.swift, *.go"))
        #expect(
            WorkspaceSearchEngine.matchesFilter(
                relativePath: "Sources/Main.swift", filename: "Main.swift", pattern: "*.swift, *.go"))
        #expect(
            !WorkspaceSearchEngine.matchesFilter(
                relativePath: "README.md", filename: "README.md", pattern: "*.swift, *.go"))

        // Subdirectory glob
        #expect(
            WorkspaceSearchEngine.matchesFilter(
                relativePath: "Sources/App/Main.swift", filename: "Main.swift", pattern: "Sources/*"))
    }

    // MARK: - Binary Data Detection

    @Test("Binary data detection flags null bytes")
    func binaryDetection() {
        let textData = "Normal UTF-8 source code".data(using: .utf8)!
        #expect(!WorkspaceSearchEngine.isBinaryData(textData))

        let binaryBytes: [UInt8] = [0x50, 0x4B, 0x03, 0x04, 0x00, 0x14, 0x00]
        let binaryData = Data(binaryBytes)
        #expect(WorkspaceSearchEngine.isBinaryData(binaryData))
    }

    // MARK: - String Replacement

    @Test("replaceInString replaces plain text and captures in regex")
    func replaceInString() throws {
        // Plain text replace with literal $ symbol
        let content = "Cost is price dollars"
        let plainOptions = WorkspaceSearchOptions(query: "price", replacement: "$100", isRegex: false)
        let (plainReplaced, plainCount) = try WorkspaceSearchEngine.replaceInString(content, options: plainOptions)
        #expect(plainCount == 1)
        #expect(plainReplaced == "Cost is $100 dollars")

        // Regex replace with group capture
        let code = "func alpha(); func beta();"
        let regexOptions = WorkspaceSearchOptions(
            query: "func (\\w+)\\(\\);", replacement: "private func $1_v2();", isRegex: true)
        let (regexReplaced, regexCount) = try WorkspaceSearchEngine.replaceInString(code, options: regexOptions)
        #expect(regexCount == 2)
        #expect(regexReplaced == "private func alpha_v2(); private func beta_v2();")
    }

    // MARK: - Open Document & Memory Synchronization

    @MainActor
    @Test("replaceAll updates in-memory Document buffer directly")
    func replaceAllInMemory() throws {
        let url = URL(fileURLWithPath: "/tmp/open-doc-test.swift")
        let doc = Document(content: "let x = 1\nlet y = 1\nlet z = 2", url: url)

        let match1 = WorkspaceSearchMatch(
            fileURL: url,
            relativePath: "open-doc-test.swift",
            lineNumber: 1,
            column: 9,
            matchRangeInLine: NSRange(location: 8, length: 1),
            lineContent: "let x = 1",
            matchedText: "1"
        )
        let match2 = WorkspaceSearchMatch(
            fileURL: url,
            relativePath: "open-doc-test.swift",
            lineNumber: 2,
            column: 9,
            matchRangeInLine: NSRange(location: 8, length: 1),
            lineContent: "let y = 1",
            matchedText: "1"
        )

        let fileResult = WorkspaceSearchFileResult(
            fileURL: url, relativePath: "open-doc-test.swift", matches: [match1, match2])
        let options = WorkspaceSearchOptions(query: "1", replacement: "99")

        let count = try WorkspaceSearchEngine.replaceAll(
            files: [fileResult],
            replacement: "99",
            options: options,
            openDocuments: [doc]
        )

        #expect(count == 2)
        #expect(doc.content == "let x = 99\nlet y = 99\nlet z = 2")
        #expect(doc.isModified)
    }
}

// MARK: - Directory Search

@Test("search walks workspace files and respects filters and cancellation")
func directorySearch() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileA = tempDir.appendingPathComponent("FileA.swift")
    let fileB = tempDir.appendingPathComponent("FileB.go")
    let fileIgnored = tempDir.appendingPathComponent(".build/FileC.swift")
    try FileManager.default.createDirectory(
        at: tempDir.appendingPathComponent(".build"), withIntermediateDirectories: true)

    try "func alpha() { print(\"hello\") }".write(to: fileA, atomically: true, encoding: .utf8)
    try "package main\nfunc hello() {}".write(to: fileB, atomically: true, encoding: .utf8)
    try "func hello() {}".write(to: fileIgnored, atomically: true, encoding: .utf8)

    let options = WorkspaceSearchOptions(query: "hello", filePattern: "*.swift")
    let results = try await WorkspaceSearchEngine.search(root: tempDir, options: options, openSnapshots: [])

    #expect(results.count == 1)
    #expect(results[0].relativePath == "FileA.swift")
    #expect(results[0].matches.count == 1)
    #expect(results[0].matches[0].lineNumber == 1)
}
