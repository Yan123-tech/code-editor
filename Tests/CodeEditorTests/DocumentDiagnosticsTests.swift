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

    @Test("continuous typing flips modified state and allows live diagnostic cycle")
    func liveTypingAndDiagnosticCycle() {
        let doc = Document(content: "package main\n\nfunc main() {}\n")
        #expect(!doc.isModified)

        // Typing random characters marks document modified
        doc.setContent("package main\n\nfunc main() {\n  asdf\n}\n")
        #expect(doc.isModified)

        // Live linter emits syntax error diagnostic
        let errDiag = DocumentDiagnostic(
            range: TextSelection(start: 31, end: 35),
            severity: .error,
            message: "undefined: asdf",
            source: "gopls"
        )
        doc.setDiagnostics([errDiag])
        #expect(doc.diagnostics.count == 1)
        #expect(doc.diagnostics.first?.source == "gopls")

        // User resolves the syntax error
        doc.setContent("package main\n\nfunc main() {\n  println(\"ok\")\n}\n")
        doc.setDiagnostics([])
        #expect(doc.diagnostics.isEmpty)
        #expect(doc.isModified)
    }

    @Test("DocumentDiagnostic Identifiable produces stable and distinguishing IDs")
    func diagnosticIdentifiable() {
        let diag1 = DocumentDiagnostic(
            range: TextSelection(start: 10, end: 15),
            severity: .error,
            message: "syntax error",
            source: "swift"
        )
        let diag2 = DocumentDiagnostic(
            range: TextSelection(start: 10, end: 15),
            severity: .error,
            message: "syntax error",
            source: "swift"
        )
        let diag3 = DocumentDiagnostic(
            range: TextSelection(start: 20, end: 25),
            severity: .warning,
            message: "unused variable",
            source: "swift"
        )

        #expect(diag1.id == diag2.id)
        #expect(diag1.id != diag3.id)
        #expect(!diag1.id.isEmpty)
    }

    @Test("document diagnostic sorting orders by line, severity, and column")
    func diagnosticSorting() {
        let doc = Document(content: "line 1\nline 2 error here\nline 3 warning")
        let diag1 = DocumentDiagnostic(
            range: TextSelection(start: 7, end: 13),  // line 2
            severity: .warning,
            message: "warning in line 2"
        )
        let diag2 = DocumentDiagnostic(
            range: TextSelection(start: 7, end: 13),  // line 2
            severity: .error,
            message: "error in line 2"
        )
        let diag3 = DocumentDiagnostic(
            range: TextSelection(start: 25, end: 32),  // line 3
            severity: .error,
            message: "error in line 3"
        )
        let diags = [diag3, diag1, diag2]

        let sorted = diags.sorted { lhs, rhs in
            let lhsPos = doc.lineAndColumn(for: lhs.range.start) ?? (line: 0, column: 0)
            let rhsPos = doc.lineAndColumn(for: rhs.range.start) ?? (line: 0, column: 0)
            if lhsPos.line != rhsPos.line {
                return lhsPos.line < rhsPos.line
            }
            if lhs.severity.rawValue != rhs.severity.rawValue {
                return lhs.severity.rawValue < rhs.severity.rawValue
            }
            return lhsPos.column < rhsPos.column
        }

        #expect(sorted[0].message == "error in line 2")
        #expect(sorted[1].message == "warning in line 2")
        #expect(sorted[2].message == "error in line 3")
    }
}
