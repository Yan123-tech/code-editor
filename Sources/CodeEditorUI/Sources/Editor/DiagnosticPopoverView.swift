import AppKit
import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Floating tooltip popover displayed when hovering over diagnostic error or warning lines.
public struct DiagnosticPopoverView: View {
    public let diagnostics: [DocumentDiagnostic]
    public let theme: Theme

    public init(diagnostics: [DocumentDiagnostic], theme: Theme) {
        self.diagnostics = diagnostics
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.compact) {
            ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diag in
                row(for: diag)
            }
        }
        .padding(Metrics.Space.regular)
        .frame(minWidth: 260, maxWidth: 440)
        .background(theme.chrome.overlayBackground.color)
    }

    @ViewBuilder
    private func row(for diag: DocumentDiagnostic) -> some View {
        HStack(alignment: .top, spacing: Metrics.Space.compact) {
            Image(systemName: iconName(for: diag.severity))
                .foregroundStyle(iconColor(for: diag.severity))
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(severityTitle(for: diag.severity))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(iconColor(for: diag.severity))

                    if let source = diag.source, !source.isEmpty {
                        Text(source)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText.color)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.chrome.border.color.opacity(0.3))
                            )
                    }
                }

                Text(diag.message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private func severityTitle(for severity: DocumentDiagnosticSeverity) -> String {
        switch severity {
        case .error: return "Error"
        case .warning: return "Warning"
        case .information: return "Information"
        case .hint: return "Hint"
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
