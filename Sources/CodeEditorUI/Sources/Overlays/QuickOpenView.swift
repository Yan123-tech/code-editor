import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// The ⌘P palette: query field over ranked, highlighted results.
///
/// Presented as a window-level overlay rather than a sheet so it does not dim the
/// editor behind it and dismisses on Esc without ceremony. Results are plain
/// `QuickOpenMatch` values from `QuickOpenIndex`; this view only renders them.
public struct QuickOpenView: View {
    @Binding var query: String
    let matches: [QuickOpenMatch]
    let theme: Theme
    let isIndexing: Bool
    let onOpen: (URL) -> Void
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool
    @State private var selectionIndex = 0

    public init(
        query: Binding<String>,
        matches: [QuickOpenMatch],
        theme: Theme,
        isIndexing: Bool,
        onOpen: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        self._query = query
        self.matches = matches
        self.theme = theme
        self.isIndexing = isIndexing
        self.onOpen = onOpen
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            field

            if matches.isEmpty {
                empty
            } else {
                results
            }
        }
        .frame(width: 520)
        .background(overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.panel, style: .continuous)
                .strokeBorder(theme.chrome.border.color, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .onAppear { isFieldFocused = true }
    }

    // MARK: - Parts

    @ViewBuilder
    private var overlayBackground: some View {
        if theme.chrome.usesMaterials {
            Rectangle().fill(.regularMaterial)
        } else {
            Rectangle().fill(theme.chrome.overlayBackground.color)
        }
    }

    private var field: some View {
        HStack(spacing: Metrics.Space.regular) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Go to file…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .rounded))
                .focused($isFieldFocused)
                .onSubmit(acceptSelected)
                .onKeyPress(.downArrow) {
                    selectionIndex = min(selectionIndex + 1, max(matches.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectionIndex = max(selectionIndex - 1, 0)
                    return .handled
                }
                .onExitCommand(perform: onClose)

            if isIndexing {
                ProgressView()
                    .controlSize(.small)
                    .help("Indexing workspace")
            }
        }
        .padding(.horizontal, Metrics.Space.loose)
        .padding(.vertical, Metrics.Space.relaxed)
    }

    private var empty: some View {
        Text(query.isEmpty ? "Type to search the workspace" : "No matches")
            .font(Typography.emptyBody)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.Space.spacious)
            .padding(.bottom, Metrics.Space.relaxed)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.url) { index, match in
                        row(match, isSelected: index == clampedSelection)
                            .id(match.url)
                            .onTapGesture {
                                selectionIndex = index
                                open(match)
                            }
                    }
                }
                .padding(Metrics.Space.compact)
                .padding(.bottom, Metrics.Space.compact)
            }
            .frame(maxHeight: 320)
            .onChange(of: selectionIndex) { _, newIndex in
                guard !matches.isEmpty else { return }
                proxy.scrollTo(matches[clampedSelection].url, anchor: .center)
            }
        }
    }

    private var clampedSelection: Int {
        min(selectionIndex, max(matches.count - 1, 0))
    }

    private func row(_ match: QuickOpenMatch, isSelected: Bool) -> some View {
        HStack(spacing: Metrics.Space.regular) {
            Image(systemName: iconName(for: match))
                .font(Typography.sidebarRow)
                .foregroundStyle(isSelected ? theme.chrome.accent.color : .secondary)
                .frame(width: 16)

            highlighted(match)
                .font(Typography.sidebarRow)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.Space.regular)
        .padding(.vertical, Metrics.Space.compact)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.row, style: .continuous)
                .fill(isSelected ? theme.chrome.rowSelected.color : .clear)
        )
        .contentShape(Rectangle())
    }

    private func iconName(for match: QuickOpenMatch) -> String {
        let name = match.relativePath.lowercased()
        if name.hasSuffix("/") || !name.contains(".") { return "folder" }
        return "doc"
    }

    /// The path with matched characters emphasised over the dimmed remainder.
    /// Built by `Text` concatenation with per-run styles; matched runs use the
    /// text colour, unmatched the secondary colour.
    private func highlighted(_ match: QuickOpenMatch) -> Text {
        let path = match.relativePath
        let units = Array(path.utf16)
        let dimmed = theme.secondaryText.color
        let emphasized = theme.text.color

        var result = Text("")
        var cursor = 0
        for range in match.highlightRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard range.lowerBound >= cursor, range.upperBound <= units.count else { continue }

            if range.lowerBound > cursor {
                result =
                    result
                    + Text(
                        String(decoding: units[cursor..<range.lowerBound], as: UTF16.self)
                    ).foregroundColor(dimmed)
            }
            result =
                result
                + Text(
                    String(decoding: units[range], as: UTF16.self)
                ).foregroundColor(emphasized)
            cursor = range.upperBound
        }
        if cursor < units.count {
            result =
                result
                + Text(
                    String(decoding: units[cursor...], as: UTF16.self)
                ).foregroundColor(dimmed)
        }
        return result
    }

    // MARK: - Actions

    private func acceptSelected() {
        guard !matches.isEmpty else { return }
        open(matches[clampedSelection])
    }

    private func open(_ match: QuickOpenMatch) {
        onOpen(match.url)
        onClose()
    }
}
