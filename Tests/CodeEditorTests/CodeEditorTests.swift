import Foundation
import Testing

@testable import CodeEditorCore

// MARK: - LineEnding

@Suite("LineEnding")
struct LineEndingTests {
    @Test("detects CRLF over LF and CR")
    func detection() {
        #expect(LineEnding.detect(from: "a\r\nb") == .crlf)
        #expect(LineEnding.detect(from: "a\nb") == .lf)
        #expect(LineEnding.detect(from: "a\rb") == .cr)
        #expect(LineEnding.detect(from: "no line endings") == .lf)
    }
}

// MARK: - Language

@MainActor
@Suite("Language")
struct LanguageTests {
    @Test("resolves languages from file extensions")
    func fromExtension() {
        #expect(Document.language(for: URL(fileURLWithPath: "/tmp/Main.swift")) == .swift)
        #expect(Document.language(for: URL(fileURLWithPath: "/tmp/app.tsx")) == .typescript)
        #expect(Document.language(for: URL(fileURLWithPath: "/tmp/README.md")) == .markdown)
        #expect(Document.language(for: URL(fileURLWithPath: "/tmp/unknown.zzz")) == .unknown)
    }
}

// MARK: - TextSelection

@Suite("TextSelection")
struct TextSelectionTests {
    @Test("normalizes inverted ranges")
    func normalizes() {
        let selection = TextSelection(start: 10, end: 4)
        #expect(selection.start == 4)
        #expect(selection.end == 10)
        #expect(selection.length == 6)
    }

    @Test("builds from location and length")
    func fromLocationAndLength() {
        let selection = TextSelection(location: 3, length: 4)
        #expect(selection.start == 3)
        #expect(selection.end == 7)
        #expect(selection.nsRange == NSRange(location: 3, length: 4))
    }
}

// MARK: - Document

@MainActor
@Suite("Document")
struct DocumentTests {
    @Test("splits content into lines without a trailing empty line")
    func lineSplitting() {
        #expect(Document(content: "a\nb\nc").lineCount == 3)
        #expect(Document(content: "a\nb\nc\n").lineCount == 3)
        #expect(Document(content: "").lineCount == 1)
        #expect(Document(content: "single").line(0) == "single")
    }

    @Test("maps offsets to line and column and back")
    func offsetMath() {
        let document = Document(content: "abc\ndef\nghi")

        #expect(document.lineAndColumn(for: 0)?.line == 0)
        #expect(document.lineAndColumn(for: 0)?.column == 0)
        #expect(document.lineAndColumn(for: 5)?.line == 1)
        #expect(document.lineAndColumn(for: 5)?.column == 1)

        #expect(document.offset(forLine: 1, column: 0) == 4)
        // "abc\n" + "def\n" is 8 bytes, so line 2 column 2 is byte 10.
        #expect(document.offset(forLine: 2, column: 2) == 10)
        #expect(document.offset(forLine: 9, column: 0) == nil)
    }

    @Test("clamps selections to the content bounds")
    func selectionClamping() {
        let document = Document(content: "hello")

        document.setSelection(from: -10, to: 100)
        #expect(document.selection.start == 0)
        #expect(document.selection.end == 5)
        #expect(document.selectedText == "hello")

        document.setSelection(from: 1, to: 3)
        #expect(document.selectedText == "el")
    }

    @Test("inserting at a zero-length selection succeeds")
    func insertAtCursor() {
        let document = Document(content: "ac")
        document.setSelection(location: 1)
        document.insert("b")

        #expect(document.content == "abc")
        #expect(document.isModified)
    }

    @Test("inserting replaces the selected range and moves the caret")
    func insertReplacesSelection() {
        let document = Document(content: "hello world")
        document.setSelection(from: 0, to: 5)
        document.insert("goodbye")

        #expect(document.content == "goodbye world")
        #expect(document.selection.start == 7)
        #expect(document.selection.end == 7)
    }

    @Test("deleting removes the selection")
    func deleteSelection() {
        let document = Document(content: "abc def")
        document.setSelection(from: 3, to: 4)
        document.deleteSelection()

        #expect(document.content == "abcdef")
        #expect(document.selection.start == 3)
        #expect(document.selection.isEmpty)
    }

    @Test("setContent ignores unchanged content")
    func setContentNoOp() {
        let document = Document(content: "same")
        document.setContent("same")
        #expect(!document.isModified)
    }

    @Test("changing the line ending normalizes content and lines")
    func lineEndingConversion() {
        let document = Document(content: "a\nb\nc")
        document.setLineEnding(.crlf)

        #expect(document.lineEnding == .crlf)
        #expect(document.content == "a\r\nb\r\nc")
        #expect(document.lineCount == 3)
        // "a\r\n" is 3 bytes, so line 1 starts at byte 3.
        #expect(document.offset(forLine: 1, column: 0) == 3)
    }

    @Test("covers whole lines with their trailing newline")
    func lineRanges() {
        let document = Document(content: "aa\nbb\ncc")
        let range = document.range(ofLines: 0, to: 1)

        #expect(range?.location == 0)
        #expect(range?.length == 6)
    }

    @Test("reports character and line counts")
    func counts() {
        let document = Document(content: "héllo")
        #expect(document.characterCount == "héllo".utf8.count)
        #expect(document.lineCount == 1)
    }
}

// MARK: - Document persistence

@MainActor
@Suite("Document persistence")
struct DocumentPersistenceTests {
    @Test("saves and reloads from disk")
    func saveAndLoad() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codeeditor-test-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: url) }

        let document = Document(content: "let x = 1\n", language: .swift)
        try await document.save(to: url)

        #expect(!document.isModified)
        #expect(document.url == url)

        let reloaded = try await Document.load(from: url)
        #expect(reloaded.content == "let x = 1\n")
        #expect(reloaded.language == .swift)
        #expect(reloaded.lineCount == 1)
    }

    @Test("throws when saving an untitled document")
    func saveWithoutURL() async {
        let document = Document.untitled()
        await #expect(throws: DocumentError.noURL) {
            try await document.save()
        }
    }
}

// MARK: - DocumentManager

@MainActor
@Suite("DocumentManager")
struct DocumentManagerTests {
    @Test("opening a file twice reuses the document")
    func openReuses() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codeeditor-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        let manager = DocumentManager()
        let first = try await manager.open(url)
        let second = try await manager.open(url)

        #expect(first === second)
        #expect(manager.openCount == 1)
        #expect(manager.isDocumentOpen(at: url))
    }

    @Test("closing the active document focuses a neighbour")
    func closeFocusesNeighbour() async throws {
        let manager = DocumentManager()
        let first = manager.open(Document.untitled())
        let second = manager.open(Document.untitled())

        #expect(manager.activeDocument === second)

        manager.close(second)
        #expect(manager.activeDocument === first)
        #expect(manager.openCount == 1)
    }

    @Test("tracks modified documents")
    func tracksModified() {
        let manager = DocumentManager()
        let document = manager.open(Document.untitled())

        #expect(!manager.hasModifiedDocuments)
        document.setContent("changed")
        #expect(manager.hasModifiedDocuments)
    }
}

// MARK: - TextSelectionManager

@MainActor
@Suite("TextSelectionManager")
struct TextSelectionManagerTests {
    @Test("starts with a single empty selection")
    func initialState() {
        let manager = TextSelectionManager()
        #expect(manager.selections.count == 1)
        #expect(manager.hasOnlyCursors)
        #expect(!manager.hasMultipleSelections)
    }

    @Test("keeps the primary selection first")
    func primarySelection() {
        let manager = TextSelectionManager()
        manager.setSelection(from: 5, to: 10)
        manager.addSelection(TextSelection(start: 0, end: 1))

        #expect(manager.selections.count == 2)
        #expect(manager.hasMultipleSelections)
        #expect(manager.primarySelection == TextSelection(start: 5, end: 10))
    }

    @Test("does not remove the last remaining selection")
    func cannotRemoveLastSelection() {
        let manager = TextSelectionManager()
        manager.setSelection(from: 0, to: 3)
        manager.removeSelection(TextSelection(start: 0, end: 3))

        #expect(manager.selections.count == 1)
    }

    @Test("joins selected text in document order")
    func selectedText() {
        let manager = TextSelectionManager()
        manager.setSelection(from: 5, to: 7)
        manager.addSelection(TextSelection(start: 0, end: 2))

        #expect(manager.selectedText(in: "abcdeFGH") == "abFG")
    }
}

// MARK: - FileSystemManager

@MainActor
@Suite("FileSystemManager")
struct FileSystemManagerTests {
    /// In-memory provider so tests never touch the real disk.
    final class StubProvider: FileSystemProvider, @unchecked Sendable {
        var directories: Set<URL>
        var files: [URL: String]

        init(directories: Set<URL> = [], files: [URL: String] = [:]) {
            self.directories = directories
            self.files = files
        }

        private func children(of url: URL) -> [URL] {
            let prefix = url.standardizedFileURL.path + "/"
            let listed = files.keys.filter { path -> Bool in
                let p = path.standardizedFileURL.path
                return p.hasPrefix(prefix) && !p.dropFirst(prefix.count).contains("/")
            }
            let subdirs = directories.filter { dir -> Bool in
                let p = dir.standardizedFileURL.path
                return p.hasPrefix(prefix) && !p.dropFirst(prefix.count).contains("/")
            }
            return (listed + subdirs).sorted { $0.path < $1.path }
        }

        func contentsOfDirectory(at url: URL) throws -> [URL] {
            children(of: url)
        }

        func fileExists(at url: URL) -> Bool {
            files[url] != nil || directories.contains(url)
        }

        func isDirectory(at url: URL) -> Bool { directories.contains(url) }
        func createDirectory(at url: URL) throws { directories.insert(url) }
        func createFile(at url: URL, contents: Data) throws { files[url] = String(decoding: contents, as: UTF8.self) }

        func removeItem(at url: URL) throws {
            files[url] = nil
            directories.remove(url)
        }

        func moveItem(at srcURL: URL, to dstURL: URL) throws {
            if let content = files[srcURL] {
                files[dstURL] = content
                files[srcURL] = nil
            }
        }

        func readFile(at url: URL) throws -> Data { Data((files[url] ?? "").utf8) }
        func writeFile(at url: URL, data: Data) throws { files[url] = String(decoding: data, as: UTF8.self) }

        func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
            [.size: (files[url]?.utf8.count ?? 0)]
        }
    }

    @Test("rejects a root that is not a directory")
    func rejectsNonDirectory() async {
        let root = URL(fileURLWithPath: "/tmp/stub-root")
        let provider = StubProvider(files: [root: "x"])
        let manager = FileSystemManager(provider: provider)

        manager.setRoot(root)
        #expect(manager.rootURL == nil)
        #expect(manager.errorMessage != nil)
    }

    @Test("loads children and sorts directories first")
    func sortsDirectoriesFirst() async {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let provider = StubProvider(
            directories: [root.appendingPathComponent("zeta")],
            files: [
                root.appendingPathComponent("b.txt"): "b",
                root.appendingPathComponent("a.txt"): "a",
            ]
        )
        let manager = FileSystemManager(provider: provider)

        manager.setRoot(root)
        await manager.load(root)

        #expect(manager.children(of: root).map(\.name) == ["zeta", "a.txt", "b.txt"])
    }

    @Test("creating a file adds it to the listing")
    func createFile() async throws {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let provider = StubProvider(directories: [root])
        let manager = FileSystemManager(provider: provider)
        manager.setRoot(root)
        await manager.load(root)

        try await manager.createFile(named: "new.txt", in: root)
        #expect(manager.children(of: root).map(\.name) == ["new.txt"])
    }

    @Test("renaming replaces the entry")
    func renameFile() async throws {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let provider = StubProvider(directories: [root], files: [root.appendingPathComponent("old.txt"): "x"])
        let manager = FileSystemManager(provider: provider)
        manager.setRoot(root)
        await manager.load(root)

        let item = try #require(manager.children(of: root).first)
        try await manager.rename(item, to: "new.txt")
        #expect(manager.children(of: root).map(\.name) == ["new.txt"])
    }

    @Test("tracks expanded folders")
    func expansion() async throws {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let child = root.appendingPathComponent("dir")
        let provider = StubProvider(directories: [root, child])
        let manager = FileSystemManager(provider: provider)
        manager.setRoot(root)
        await manager.load(root)

        let item = try #require(manager.children(of: root).first)
        #expect(!manager.isExpanded(item.url))

        manager.toggleExpansion(of: item)
        #expect(manager.isExpanded(item.url))
        await manager.load(child)

        manager.toggleExpansion(of: item)
        #expect(!manager.isExpanded(item.url))
    }

    @Test("keys the cache on standardized paths, not URL identity")
    func cacheKeysIgnoreTrailingSlash() async throws {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let provider = StubProvider(directories: [root], files: [root.appendingPathComponent("a.txt"): "a"])
        let manager = FileSystemManager(provider: provider)

        manager.setRoot(root)
        await manager.load(root)

        // Same directory, expressed with a trailing slash.
        let withSlash = URL(fileURLWithPath: "/tmp/stub/")
        #expect(manager.children(of: withSlash).map(\.name) == ["a.txt"])
    }

    @Test("reveal expands every ancestor of a deeply nested file")
    func revealExpandsAncestors() async {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let sub = root.appendingPathComponent("Sources")
        let nested = sub.appendingPathComponent("App")
        let file = nested.appendingPathComponent("Main.swift")
        let provider = StubProvider(directories: [root, sub, nested], files: [file: "x"])
        let manager = FileSystemManager(provider: provider)

        manager.setRoot(root)
        await manager.load(root)
        #expect(!manager.isExpanded(sub))

        await manager.reveal(file)

        #expect(manager.isExpanded(sub))
        #expect(manager.isExpanded(nested))
        // The file's own directory is loaded, the file itself is not a directory to expand.
        #expect(!manager.children(of: nested).isEmpty)
    }

    @Test("reveal is a no-op outside the root")
    func revealOutsideRoot() async {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let provider = StubProvider(directories: [root])
        let manager = FileSystemManager(provider: provider)
        manager.setRoot(root)
        await manager.load(root)

        await manager.reveal(URL(fileURLWithPath: "/elsewhere/thing.swift"))
        #expect(manager.children(of: root).isEmpty)
    }

    @Test("reveal does not reload already-expanded ancestors")
    func revealSkipsExpanded() async throws {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let sub = root.appendingPathComponent("dir")
        let file = sub.appendingPathComponent("a.txt")
        let provider = StubProvider(directories: [root, sub], files: [file: "a"])
        let manager = FileSystemManager(provider: provider)
        manager.setRoot(root)
        await manager.load(root)

        manager.toggleExpansion(of: try #require(manager.children(of: root).first))
        await manager.load(sub)
        await manager.reveal(file)
        #expect(manager.isExpanded(sub))
    }

    @Test("clearError dismisses the error so an alert can close")
    func clearErrorDismisses() {
        let root = URL(fileURLWithPath: "/tmp/stub")
        let provider = StubProvider(files: [root: "x"])
        let manager = FileSystemManager(provider: provider)
        manager.setRoot(root)
        #expect(manager.errorMessage != nil)

        manager.clearError()
        #expect(manager.errorMessage == nil)
    }
}

// MARK: - FileSystemItem

@Suite("FileSystemItem")
struct FileSystemItemTests {
    @Test("detects hidden files")
    func hidden() {
        #expect(FileSystemItem(url: URL(fileURLWithPath: "/tmp/.env"), isDirectory: false).isHidden)
        #expect(!FileSystemItem(url: URL(fileURLWithPath: "/tmp/env"), isDirectory: false).isHidden)
    }

    @Test("identifies directories and files")
    func iconNames() {
        #expect(FileSystemItem(url: URL(fileURLWithPath: "/tmp/src"), isDirectory: true).iconName == "folder")
        #expect(FileSystemItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false).iconName == "swift")
    }
}
