import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// The readout strip under the editor: caret position, selection, then — pushed to
/// the trailing edge — encoding, line ending and language.
///
/// The byte count is gone; it flattered the machine and told the reader nothing.
public struct StatusBarView: View {
    let appState: AppState

    @State private var isDiagnosticsPopoverPresented = false
    @State private var isDiagnosticsHovered = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 0) {
            if let document = appState.documentManager.activeDocument {
                item("Ln \(appState.editorState.caretLine + 1), Col \(appState.editorState.caretColumn + 1)")

                if !appState.editorState.selectedLines.isEmpty {
                    separator
                    let count = appState.editorState.selectedLines.count
                    item(count == 1 ? "1 line selected" : "\(count) lines selected")
                }

                Spacer(minLength: 0)

                item("UTF-8")
                separator
                item(document.lineEnding == .lf ? "LF" : document.lineEnding == .crlf ? "CRLF" : "CR")
                separator
                item(document.language.displayName)

                if appState.pendingExternalChange != nil {
                    separator
                    item("⚠️ Changed on disk")
                }

                if !document.diagnostics.isEmpty {
                    separator
                    diagnosticSummary(for: document)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .font(Typography.statusBar)
        .foregroundStyle(appState.theme.secondaryText.color)
        .padding(.horizontal, Metrics.Space.regular)
        .frame(height: Metrics.Height.statusBar)
        .background(backgroundFill)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appState.theme.chrome.border.color)
                .frame(height: 1)
        }
    }

    /// Opaque base first, then material: the status bar also sits flush against a scroll view,
    /// and a translucent fill lets overscrolled content bleed through. See `TabBarView.stripFill`.
    @ViewBuilder
    private var backgroundFill: some View {
        Rectangle().fill(appState.theme.background.color)
        if appState.theme.chrome.usesMaterials {
            Rectangle().fill(.thinMaterial)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(appState.theme.chrome.border.color)
            .frame(width: 1, height: 9)
            .padding(.horizontal, Metrics.Space.regular)
    }

    private func item(_ label: String) -> some View {
        Text(label)
            .padding(.vertical, 2)
            .fixedSize()
    }

    /// A compact error/warning count button, coloured by the worst severity present.
    /// Clicking opens a scrollable pop-up list of problems with click-to-jump navigation.
    @ViewBuilder
    private func diagnosticSummary(for document: CodeEditorCore.Document) -> some View {
        let errors = document.diagnostics.filter { $0.severity == .error }.count
        let warnings = document.diagnostics.filter { $0.severity == .warning }.count
        let color: Color = errors > 0 ? appState.theme.semantic.danger.color : appState.theme.semantic.warning.color

        Button {
            isDiagnosticsPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                if errors > 0 {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                } else if warnings > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text("\(errors) error\(errors == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s")")
            }
            .foregroundStyle(color)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isDiagnosticsHovered ? appState.theme.chrome.rowHover.color : Color.clear)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { isDiagnosticsHovered = $0 }
        .popover(isPresented: $isDiagnosticsPopoverPresented, arrowEdge: .bottom) {
            DiagnosticsListView(
                document: document,
                theme: appState.theme,
                onSelect: { diagnostic in
                    appState.jumpTo(diagnostic: diagnostic, in: document)
                    isDiagnosticsPopoverPresented = false
                }
            )
        }
    }
}
