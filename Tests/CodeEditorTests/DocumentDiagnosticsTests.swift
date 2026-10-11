import Foundation
import Testing

@testable import CodeEditorCore

@MainActor
@Suite("Document diagnostics")
struct DocumentDiagnosticsTests {

    @Test("setDiagnostics stores and replaces diagnostics")
    func storeReplace() {
        let doc = Document(content: "let x = 1")
        #expect(doc.diagnostics.isEmpty)

        let diag = DocumentDiagnostic(
            range: TextSelection(start: 4, end: 5),
            severity: .error,
            message: "unexpected identifier"
        )
        doc.setDiagnostics([diag])
        #expect(doc.diagnostics.count == 1)
        #expect(doc.diagnostics.first?.message == "unexpected identifier")
        #expect(doc.diagnostics.first?.severity == .error)

        doc.setDiagnostics([])
        #expect(doc.diagnostics.isEmpty)
    }

    @Test("diagnostic range maps to a valid NSRange")
    func rangeToNSRange() {
        let doc = Document(content: "func foo() {\n  bar()\n}")
        let start = doc.offset(forLine: 1, column: 2)!  // line 2, col 2 → "bar"
        let end = doc.offset(forLine: 1, column: 5)!
        let diag = DocumentDiagnostic(
            range: TextSelection(start: start, end: end),
            severity: .warning,
            message: "unused"
        )
        doc.setDiagnostics([diag])
        let nsRange = doc.nsRange(from: diag.range.start, to: diag.range.end)
        #expect(nsRange?.location == start)
        #expect(nsRange?.length == 3)
    }
}
