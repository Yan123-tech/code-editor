import Foundation

/// The severity of a diagnostic, mirroring the LSP `DiagnosticSeverity` ranking.
///
/// Kept in `CodeEditorCore` so `Document` can store diagnostics without importing
/// `CodeEditorLSP`; the coordinator maps from the LSP type.
public enum DocumentDiagnosticSeverity: Int, CaseIterable, Sendable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

/// A diagnostic attached to a document, expressed as UTF-8 content offsets so it stays
/// in the same coordinate space as `TextSelection` and `Document.nsRange`.
///
/// Built from the LSP `Diagnostic` by `LSPTextViewCoordinator`; the Core model never
/// imports the LSP module.
public struct DocumentDiagnostic: Equatable, Sendable {
    /// Offset range of the diagnostic, matching `Document` offsets.
    public let range: TextSelection
    public let severity: DocumentDiagnosticSeverity
    public let message: String
    public let source: String?

    public init(range: TextSelection, severity: DocumentDiagnosticSeverity, message: String, source: String? = nil) {
        self.range = range
        self.severity = severity
        self.message = message
        self.source = source
    }
}
