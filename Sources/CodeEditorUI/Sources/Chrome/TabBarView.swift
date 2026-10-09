import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// The tab strip above the editor.
///
/// The active tab's fill equals the canvas and its top corners are rounded, so it
/// reads as the top of the editor rather than a chip in a bar — the Xcode treatment.
/// The strip's bottom hairline runs behind the tabs; the active tab covers its own
/// segment, which is what makes the merge visible.
///
/// Every tab always offers a close button. The dirty state is a dot beside the
/// title, not a replacement for the button: swapping `×` for a dot made modified
/// tabs impossible to close without saving first.
public struct TabBarView: View {
    let documents: [CodeEditorCore.Document]
    let activeDocument: CodeEditorCore.Document?
    let theme: Theme
    let onSelect: (CodeEditorCore.Document) -> Void
    let onClose: (CodeEditorCore.Document) -> Void
    let onNew: () -> Void

    @State private var hoveredDocument: CodeEditorCore.Document?

    public init(
        documents: [CodeEditorCore.Document],
        activeDocument: CodeEditorCore.Document?,
        theme: Theme,
        onSelect: @escaping (CodeEditorCore.Document) -> Void,
        onClose: @escaping (CodeEditorCore.Document) -> Void,
        onNew: @escaping () -> Void
    ) {
        self.documents = documents
        self.activeDocument = activeDocument
        self.theme = theme
        self.onSelect = onSelect
        self.onClose = onClose
        self.onNew = onNew
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            stripFill
            stripBorder

            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(documents) { document in
                            tab(for: document)
                        }
                    }
                    .padding(.horizontal, Metrics.Space.compact)
                }

                newTabButton
                    .padding(.horizontal, Metrics.Space.regular)
            }
            .frame(height: Metrics.Height.tabStrip)
        }
        .frame(height: Metrics.Height.tabStrip)
    }

    // MARK: - Strip

    /// Materials when the palette allows them; the token fill otherwise.
    @ViewBuilder
    private var stripFill: some View {
        if theme.chrome.usesMaterials {
            Rectangle().fill(.thinMaterial)
        } else {
            Rectangle().fill(theme.chrome.barBackground.color)
        }
    }

    private var stripBorder: some View {
        Rectangle()
            .fill(theme.chrome.border.color)
            .frame(height: 1)
    }

    private var newTabButton: some View {
        Button(action: onNew) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(width: Metrics.minimumHitTarget - 8, height: Metrics.minimumHitTarget - 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("New File (⌘N)")
    }

    // MARK: - Tabs

    private func tab(for document: CodeEditorCore.Document) -> some View {
        let isActive = document === activeDocument
        let isHovered = hoveredDocument?.id == document.id

        return HStack(spacing: Metrics.Space.compact) {
            if document.isModified {
                Circle()
                    .fill(isActive ? theme.chrome.accent.color : theme.secondaryText.color)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }

            Text(document.title)
                .font(Typography.tabLabel)
                .lineLimit(1)
                .truncationMode(.middle)

            closeButton(for: document, isActive: isActive, isHovered: isHovered)
        }
        .padding(.leading, Metrics.Space.regular)
        .padding(.trailing, isActive || isHovered ? Metrics.Space.compact : Metrics.Space.regular + 8)
        .padding(.vertical, Metrics.Space.compact)
        .foregroundStyle(isActive ? theme.text.color : theme.secondaryText.color)
        .background(tabBackground(isActive: isActive, isHovered: isHovered))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Metrics.Radius.row,
                topTrailingRadius: Metrics.Radius.row
            )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredDocument = hovering ? document : (hoveredDocument?.id == document.id ? nil : hoveredDocument)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(document) }
        .help(document.name)
    }

    /// The close affordance. Always present so layout never shifts; invisible on
    /// unhovered inactive tabs so the strip stays quiet, but never replaced by the
    /// dirty dot.
    private func closeButton(
        for document: CodeEditorCore.Document,
        isActive: Bool,
        isHovered: Bool
    ) -> some View {
        Button {
            onClose(document)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 14, height: 14)
                .background(
                    Circle().fill(
                        (isActive || isHovered) ? theme.chrome.rowHover.color : .clear
                    )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isActive || isHovered ? 1 : 0)
        .disabled(!isActive && !isHovered)
        .help(document.isModified ? "Close (unsaved changes)" : "Close")
    }

    @ViewBuilder
    private func tabBackground(isActive: Bool, isHovered: Bool) -> some View {
        if isActive {
            // Matches the canvas, so the tab becomes the top of the editor.
            theme.background.color
        } else if isHovered {
            theme.chrome.tabHoverBackground.color
        } else {
            Color.clear
        }
    }
}
