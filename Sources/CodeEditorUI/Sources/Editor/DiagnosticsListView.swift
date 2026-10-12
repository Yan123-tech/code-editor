import AppKit
import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Scrollable list of problems/diagnostics for the active document.
/// Displayed as a popover when clicking the diagnostic summary in the status bar.
public struct DiagnosticsListView: View {
    public let document: CodeEditorCore.Document
    public let theme: Theme
    public let onSelect: (DocumentDiagnostic) -> Void

    @State private var hoveredDiagnosticId: String?

    public init(
        document: CodeEditorCore.Document,
        theme: Theme,
        onSelect: @escaping (DocumentDiagnostic) -> Void
    ) {
        self.document = document
        self.theme = theme
        self.onSelect = onSelect
    }

    /// Diagnostics sorted by line ascending, then column ascending.
    private var sortedDiagnostics: [DocumentDiagnostic] {
        document.diagnostics.sorted { lhs, rhs in
            let lhsPos = document.lineAndColumn(for: lhs.range.start) ?? (line: 0, column: 0)
            let rhsPos = document.lineAndColumn(for: rhs.range.start) ?? (line: 0, column: 0)
            if lhsPos.line != rhsPos.line {
                return lhsPos.line < rhsPos.line
            }
            if lhs.severity.rawValue != rhs.severity.rawValue {
                return lhs.severity.rawValue < rhs.severity.rawValue
            }
            return lhsPos.column < rhsPos.column
        }
    }

    private var errorsCount: Int {
        document.diagnostics.filter { $0.severity == .error }.count
    }

    private var warningsCount: Int {
        document.diagnostics.filter { $0.severity == .warning }.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if sortedDiagnostics.isEmpty {
                emptyState
            } else {
                diagnosticScrollView
            }
        }
        .frame(minWidth: 380, idealWidth: 420, maxWidth: 460)
        .background(theme.chrome.overlayBackground.color)
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.compact) {
            Image(systemName: "checklist")
                .foregroundStyle(theme.secondaryText.color)
                .font(.system(size: 13, weight: .semibold))

            Text("Problems")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text.color)

            if !document.title.isEmpty {
                Text("— \(document.title)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText.color)
                    .lineLimit(1)
            }

            Spacer(minLength: Metrics.Space.compact)

            HStack(spacing: 8) {
                if errorsCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.semantic.danger.color)
                            .font(.system(size: 11))
                        Text("\(errorsCount)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.semantic.danger.color)
                    }
                }
                if warningsCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.semantic.warning.color)
                            .font(.system(size: 11))
                        Text("\(warningsCount)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.semantic.warning.color)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.Space.regular)
        .padding(.vertical, Metrics.Space.compact)
    }

    private var emptyState: some View {
        HStack(spacing: Metrics.Space.compact) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.semantic.success.color)
                .font(.system(size: 15))
            Text("No problems detected in this file")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText.color)
        }
        .padding(Metrics.Space.regular)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var diagnosticScrollView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sortedDiagnostics) { diag in
                    diagnosticRow(for: diag)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .frame(maxHeight: 280)
    }

    @ViewBuilder
    private func diagnosticRow(for diag: DocumentDiagnostic) -> some View {
        let isHovered = hoveredDiagnosticId == diag.id
        let lineCol = document.lineAndColumn(for: diag.range.start)
        let line = (lineCol?.line ?? 0) + 1
        let col = (lineCol?.column ?? 0) + 1

        Button {
            onSelect(diag)
        } label: {
            HStack(alignment: .top, spacing: Metrics.Space.compact) {
                Image(systemName: iconName(for: diag.severity))
                    .foregroundStyle(iconColor(for: diag.severity))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Ln \(line), Col \(col)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText.color)

                        if let source = diag.source, !source.isEmpty {
                            Text(source)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.secondaryText.color)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(theme.chrome.border.color.opacity(0.3))
                                )
                        }

                        Spacer(minLength: 0)
                    }

                    Text(diag.message)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text.color)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? theme.chrome.rowHover.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredDiagnosticId = hovering ? diag.id : (hoveredDiagnosticId == diag.id ? nil : hoveredDiagnosticId)
        }
    }

    private func iconName(for severity: DocumentDiagnosticSeverity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .information: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }

    private func iconColor(for severity: DocumentDiagnosticSeverity) -> Color {
        switch severity {
        case .error: return theme.semantic.danger.color
        case .warning: return theme.semantic.warning.color
        case .information: return theme.semantic.success.color
        case .hint: return theme.secondaryText.color
        }
    }
}
