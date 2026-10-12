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

    @State private var hoveredDocumentId: UUID?

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
                            TabItemView(
                                document: document,
                                isActive: document.id == activeDocument?.id,
                                isHovered: hoveredDocumentId == document.id,
                                theme: theme,
                                onSelect: { onSelect(document) },
                                onClose: { onClose(document) },
                                onHover: { isHovered in
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        hoveredDocumentId =
                                            isHovered
                                            ? document.id : (hoveredDocumentId == document.id ? nil : hoveredDocumentId)
                                    }
                                }
                            )
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
        .clipped()
    }

    // MARK: - Strip

    /// An opaque canvas-coloured base under the material.
    ///
    /// The strip sits directly above the editor with no separator, and an `NSScrollView`
    /// draws its content outside its bounds while rubber-band scrolling. A translucent
    /// material lets that overscrolled content — including the gutter — show through and
    /// appear to overlap the tab labels. The base kills the bleed-through while keeping the
    /// material's tint and the window-focus response.
    @ViewBuilder
    private var stripFill: some View {
        Rectangle().fill(theme.background.color)
        if theme.chrome.usesMaterials {
            Rectangle().fill(.thinMaterial)
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
}

// MARK: - TabItemView

private struct TabItemView: View {
    @Bindable var document: CodeEditorCore.Document
    let isActive: Bool
    let isHovered: Bool
    let theme: Theme
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: Metrics.Space.compact) {
            if document.isModified {
                Circle()
                    .fill(isActive ? theme.chrome.accent.color : theme.secondaryText.color)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }

            // `name`, not `title`: title appends " *" when modified, and the dot
            // beside the label already says that. Two indicators for one state.
            Text(document.name)
                .font(Typography.tabLabel)
                .lineLimit(1)
                .truncationMode(.middle)

            closeButton
        }
        .padding(.leading, Metrics.Space.regular)
        .padding(.trailing, isActive || isHovered ? Metrics.Space.compact : Metrics.Space.regular + 8)
        .padding(.vertical, Metrics.Space.compact)
        .foregroundStyle(isActive ? theme.text.color : theme.secondaryText.color)
        .background(tabBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Metrics.Radius.row,
                topTrailingRadius: Metrics.Radius.row
            )
        )
        .onHover { isHovering in
            onHover(isHovering)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .help(document.name)
    }

    private var closeButton: some View {
        Button {
            onClose()
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
    private var tabBackground: some View {
        if isActive {
            theme.background.color
        } else if isHovered {
            theme.chrome.tabHoverBackground.color
        } else {
            Color.clear
        }
    }
}
