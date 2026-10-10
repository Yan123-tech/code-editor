import Foundation
import Testing

@testable import CodeEditorCore

/// Guards for #6 — "A file changed on disk while open is silently overwritten."
@MainActor
@Suite("External change detection")
struct DocumentExternalChangeTests {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codeeditor-ext-\(UUID().uuidString).swift")
    }

    /// Pin the on-disk mtime ahead of the loaded baseline so a conflict is deterministic
    /// (no reliance on sub-second write ordering).
    private func bumpModificationDate(of url: URL, aheadBy seconds: TimeInterval = 60) throws {
        var target = url
        var values = URLResourceValues()
        values.contentModificationDate = Date().addingTimeInterval(seconds)
        try target.setResourceValues(values)
    }

    @Test("save is blocked when the file changed on disk since load")
    func saveBlockedByExternalChange() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "original".write(to: url, atomically: true, encoding: .utf8)

        let document = try await Document.load(from: url)
        #expect(document.content == "original")
        #expect(document.fileModificationDate != nil)
        document.setContent("modified in memory")
        #expect(document.isModified)

        // An external actor rewrites the file and advances its mtime past the loaded baseline.
        try "external".write(to: url, atomically: true, encoding: .utf8)
        try bumpModificationDate(of: url)

        do {
            try await document.save()
            Issue.record("expected DocumentError.changedOnDisk, save succeeded")
        } catch DocumentError.changedOnDisk(let savedURL, _) {
            #expect(savedURL == url)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        // The on-disk file must be left untouched by the rejected save.
        #expect(try String(contentsOf: url, encoding: .utf8) == "external")
        #expect(document.isModified)
    }

    @Test("no false positive when nothing changed on disk")
    func saveSucceedsWithNoExternalChange() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        let document = try await Document.load(from: url)
        document.setContent("hello, world")
        try await document.save()
        #expect(!document.isModified)
        #expect(document.fileModificationDate != nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == "hello, world")
    }

    @Test("revert reloads the on-disk version and clears modified")
    func revertReloadsFromDisk() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "on disk v1".write(to: url, atomically: true, encoding: .utf8)

        let document = try await Document.load(from: url)
        document.setContent("unsaved edit")
        #expect(document.isModified)

        try "on disk v2".write(to: url, atomically: true, encoding: .utf8)
        try bumpModificationDate(of: url)

        try await document.revert()
        #expect(document.content == "on disk v2")
        #expect(!document.isModified)
        #expect(document.fileModificationDate != nil)
    }

    @Test("saving resets the external-change baseline")
    func saveResetsBaseline() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "v1".write(to: url, atomically: true, encoding: .utf8)

        let document = try await Document.load(from: url)
        document.setContent("v2")
        try await document.save()
        #expect(!document.isModified)

        // No external change: re-saving succeeds (no spurious conflict).
        document.setContent("v3")
        try await document.save()
        #expect(!document.isModified)

        // An external change after the save is still detected.
        try "external".write(to: url, atomically: true, encoding: .utf8)
        try bumpModificationDate(of: url)

        do {
            try await document.save()
            Issue.record("expected DocumentError.changedOnDisk, save succeeded")
        } catch DocumentError.changedOnDisk(let savedURL, _) {
            #expect(savedURL == url)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("untitled documents are never guarded")
    func untitledIsNotGuarded() async {
        let document = Document.untitled()
        #expect(document.fileModificationDate == nil)
        await #expect(throws: DocumentError.noURL) { try await document.save() }
    }
}
