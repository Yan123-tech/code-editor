import Foundation
import Testing

@testable import CodeEditorCore

@MainActor
@Suite("Document completion positions")
struct DocumentCompletionTests {
    @Suite("lspPosition")
    @MainActor
    struct LspPosition {
        @Test("offset maps to zero-indexed line and UTF-16 character")
        func singleLine() {
            let doc = Document(content: "func foo()")
            let p0 = doc.lspPosition(for: 0)
            let p5 = doc.lspPosition(for: 5)
            let p8 = doc.lspPosition(for: 8)
            let pEnd = doc.lspPosition(for: doc.content.utf8.count)
            #expect(p0?.line == 0 && p0?.character == 0)
            #expect(p5?.line == 0 && p5?.character == 5)
            #expect(p8?.line == 0 && p8?.character == 8)
            #expect(pEnd?.line == 0 && pEnd?.character == 10)
        }

        @Test("multi-line offsets land on the right line with a fresh column")
        func multiLine() {
            let doc = Document(content: "ab\ncd")
            let p0 = doc.lspPosition(for: 0)
            let p2 = doc.lspPosition(for: 2)
            let p3 = doc.lspPosition(for: 3)
            let p5 = doc.lspPosition(for: 5)
            #expect(p0?.line == 0 && p0?.character == 0)
            #expect(p2?.line == 0 && p2?.character == 2)
            #expect(p3?.line == 1 && p3?.character == 0)
            #expect(p5?.line == 1 && p5?.character == 2)
        }
    }

    @Suite("completionPrefix")
    @MainActor
    struct CompletionPrefix {
        @Test("trailing identifier run before the caret")
        func identifierRun() {
            let doc = Document(content: "func foo()")
            #expect(doc.completionPrefix(at: 0) == "")
            #expect(doc.completionPrefix(at: 5) == "")
            #expect(doc.completionPrefix(at: 8) == "foo")
            #expect(doc.completionPrefix(at: 9) == "")
        }

        @Test("crosses line boundaries is not expected: stops at end of line")
        func stopsAtLineEnd() {
            let doc = Document(content: "foo\nbar")
            #expect(doc.completionPrefix(at: 3) == "foo")
            #expect(doc.completionPrefix(at: 4) == "")
        }
    }
}
