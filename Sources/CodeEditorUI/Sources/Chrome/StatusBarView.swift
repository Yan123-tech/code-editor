import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// The readout strip under the editor: caret position, selection, then — pushed to
/// the trailing edge — encoding, line ending and language.
///
/// The byte count is gone; it flattered the machine and told the reader nothing.
public struct StatusBarView: View {
    let appState: AppState

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
}
