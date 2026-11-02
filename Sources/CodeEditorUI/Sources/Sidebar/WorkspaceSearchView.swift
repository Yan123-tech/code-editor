import CodeEditorCore
import CodeEditorThemes
import SwiftUI

/// Sidebar navigator for workspace-wide text search and replace (⇧⌘F).
public struct WorkspaceSearchView: View {
    @Bindable var appState: AppState
    let theme: Theme

    @State private var expandedFileIDs: Set<String> = []
    @State private var hoveredMatchID: String?
    @FocusState private var isSearchFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
        self.theme = appState.theme
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchHeader
                .padding(.horizontal, Metrics.Space.regular)
                .padding(.vertical, Metrics.Space.compact)

            Divider()

            resultsContent
        }
        .background(theme.chrome.sidebarBackground.color)
        .onAppear {
            isSearchFocused = true
            syncExpandedFiles()
        }
        .onChange(of: appState.workspaceSearchResults) { _, _ in
            syncExpandedFiles()
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        VStack(spacing: Metrics.Space.compact) {
            // Search Input Row
            HStack(spacing: Metrics.Space.compact) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.isReplaceVisible.toggle()
                    }
                } label: {
                    Image(systemName: appState.isReplaceVisible ? "chevron.down" : "chevron.right")
                        .font(Typography.hint)
                        .foregroundColor(theme.secondaryText.color)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Toggle Replace")

                HStack(spacing: Metrics.Space.compact) {
                    Image(systemName: "magnifyingglass")
                        .font(Typography.statusBar)
                        .foregroundColor(theme.secondaryText.color)

                    TextField("Search", text: $appState.workspaceSearchOptions.query)
                        .textFieldStyle(.plain)
                        .font(Typography.sidebarRow)
                        .focused($isSearchFocused)
                        .onSubmit {
                            appState.performWorkspaceSearch()
                        }
                        .onChange(of: appState.workspaceSearchOptions.query) { _, _ in
                            appState.performWorkspaceSearch()
                        }

                    if !appState.workspaceSearchOptions.query.isEmpty {
                        Button {
                            appState.workspaceSearchOptions.query = ""
                            appState.performWorkspaceSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(Typography.statusBar)
                                .foregroundColor(theme.secondaryText.color)
                        }
                        .buttonStyle(.plain)
                    }

                    // Mode toggles
                    optionToggleButton(
                        label: "Aa",
                        tooltip: "Match Case",
                        isOn: $appState.workspaceSearchOptions.isCaseSensitive
                    )

                    optionToggleButton(
                        label: "W",
                        tooltip: "Match Whole Word",
                        isOn: $appState.workspaceSearchOptions.isWholeWord
                    )

                    optionToggleButton(
                        label: ".*",
                        tooltip: "Use Regular Expression",
                        isOn: $appState.workspaceSearchOptions.isRegex
                    )
                }
                .padding(.horizontal, Metrics.Space.compact)
                .padding(.vertical, 4)
                .background(theme.background.color)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.control)
                        .stroke(theme.chrome.border.color, lineWidth: 1)
                )
            }

            // Replace Input Row
            if appState.isReplaceVisible {
                HStack(spacing: Metrics.Space.compact) {
                    Color.clear.frame(width: 14, height: 14)

                    HStack(spacing: Metrics.Space.compact) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(Typography.statusBar)
                            .foregroundColor(theme.secondaryText.color)

                        TextField("Replace", text: $appState.workspaceSearchOptions.replacement)
                            .textFieldStyle(.plain)
                            .font(Typography.sidebarRow)
                            .onSubmit {
                                appState.replaceAllInWorkspace()
                            }

                        if !appState.workspaceSearchOptions.replacement.isEmpty {
                            Button {
                                appState.workspaceSearchOptions.replacement = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(Typography.statusBar)
                                    .foregroundColor(theme.secondaryText.color)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Metrics.Space.compact)
                    .padding(.vertical, 4)
                    .background(theme.background.color)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.Radius.control)
                            .stroke(theme.chrome.border.color, lineWidth: 1)
                    )

                    Button("Replace All") {
                        appState.replaceAllInWorkspace()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        appState.workspaceSearchOptions.query.isEmpty
                            || appState.workspaceSearchResults.isEmpty
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // File Filter Row
            HStack(spacing: Metrics.Space.compact) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.isFilterVisible.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(Typography.statusBar)
                        Text(appState.isFilterVisible ? "Hide Filters" : "Files to Include")
                            .font(Typography.statusBar)
                    }
                    .foregroundColor(theme.secondaryText.color)
                }
                .buttonStyle(.plain)

                Spacer()

                if !appState.workspaceSearchResults.isEmpty {
                    Button {
                        toggleExpandCollapseAll()
                    } label: {
                        Text(
                            expandedFileIDs.count == appState.workspaceSearchResults.count
                                ? "Collapse All" : "Expand All"
                        )
                        .font(Typography.statusBar)
                        .foregroundColor(theme.secondaryText.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)

            if appState.isFilterVisible {
                HStack(spacing: Metrics.Space.compact) {
                    TextField("e.g. *.swift, *.go", text: $appState.workspaceSearchOptions.filePattern)
                        .textFieldStyle(.plain)
                        .font(Typography.statusBar)
                        .padding(.horizontal, Metrics.Space.compact)
                        .padding(.vertical, 3)
                        .background(theme.background.color)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.Radius.control)
                                .stroke(theme.chrome.border.color, lineWidth: 1)
                        )
                        .onChange(of: appState.workspaceSearchOptions.filePattern) { _, _ in
                            appState.performWorkspaceSearch()
                        }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func optionToggleButton(label: String, tooltip: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            appState.performWorkspaceSearch()
        } label: {
            Text(label)
                .font(Typography.hint)
                .fontWeight(.bold)
                .foregroundColor(isOn.wrappedValue ? theme.chrome.accent.color : theme.secondaryText.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    isOn.wrappedValue
                        ? theme.chrome.accent.color.opacity(0.18)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Results Content

    private var resultsContent: some View {
        Group {
            if appState.fileSystemManager.rootURL == nil {
                emptyPrompt("Open a workspace folder to search across files.")
            } else if appState.workspaceSearchOptions.query.isEmpty {
                emptyPrompt("Type in the search field to find in workspace.")
            } else if let error = appState.workspaceSearchError {
                VStack(spacing: Metrics.Space.compact) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(theme.semantic.danger.color)
                    Text(error)
                        .font(Typography.statusBar)
                        .foregroundColor(theme.semantic.danger.color)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.isWorkspaceSearching && appState.workspaceSearchResults.isEmpty {
                VStack(spacing: Metrics.Space.compact) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching workspace…")
                        .font(Typography.statusBar)
                        .foregroundColor(theme.secondaryText.color)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.workspaceSearchResults.isEmpty {
                emptyPrompt("No results found.")
            } else {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            // Results Summary Bar
            HStack {
                Text(summaryText)
                    .font(Typography.statusBar)
                    .foregroundColor(theme.secondaryText.color)

                if appState.isWorkspaceSearching {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }

                Spacer()
            }
            .padding(.horizontal, Metrics.Space.regular)
            .padding(.vertical, 4)
            .background(theme.chrome.panelBackground.color)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.workspaceSearchResults) { fileResult in
                        fileSection(fileResult)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var summaryText: String {
        let totalMatches = appState.workspaceSearchResults.reduce(0) { $0 + $1.matchCount }
        let fileCount = appState.workspaceSearchResults.count
        let matchStr = totalMatches == 1 ? "1 result" : "\(totalMatches) results"
        let fileStr = fileCount == 1 ? "1 file" : "\(fileCount) files"
        return "\(matchStr) in \(fileStr)"
    }

    private func emptyPrompt(_ message: String) -> some View {
        VStack(spacing: Metrics.Space.compact) {
            Text(message)
                .font(Typography.emptyBody)
                .foregroundColor(theme.secondaryText.color)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Section

    private func fileSection(_ fileResult: WorkspaceSearchFileResult) -> some View {
        let isExpanded = expandedFileIDs.contains(fileResult.id)

        return VStack(alignment: .leading, spacing: 1) {
            // File Header
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    if isExpanded {
                        expandedFileIDs.remove(fileResult.id)
                    } else {
                        expandedFileIDs.insert(fileResult.id)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.hint)
                        .foregroundColor(theme.secondaryText.color)
                        .frame(width: 12)

                    Image(systemName: "doc.text")
                        .font(Typography.statusBar)
                        .foregroundColor(theme.chrome.accent.color)

                    Text(fileResult.fileURL.lastPathComponent)
                        .font(Typography.sidebarRow)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.text.color)
                        .lineLimit(1)

                    Text(directoryParent(for: fileResult.relativePath))
                        .font(Typography.statusBar)
                        .foregroundColor(theme.secondaryText.color)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(fileResult.matchCount)")
                        .font(Typography.hint)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.background.color)
                        .clipShape(Capsule())
                        .foregroundColor(theme.secondaryText.color)
                }
                .padding(.horizontal, Metrics.Space.regular)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Matches
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(fileResult.matches) { match in
                        matchRow(match)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private func matchRow(_ match: WorkspaceSearchMatch) -> some View {
        let isHovered = hoveredMatchID == match.id

        return HStack(spacing: 4) {
            Button {
                appState.jumpTo(searchMatch: match)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(match.lineNumber):")
                        .font(Typography.hint)
                        .foregroundColor(theme.secondaryText.color)
                        .frame(minWidth: 26, alignment: .trailing)

                    snippetView(for: match)
                        .font(Typography.hint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered && appState.isReplaceVisible {
                Button {
                    appState.replaceInWorkspace(
                        match: match,
                        with: appState.workspaceSearchOptions.replacement
                    )
                } label: {
                    Image(systemName: "pencil.line")
                        .font(Typography.hint)
                        .foregroundColor(theme.secondaryText.color)
                        .padding(3)
                        .background(theme.background.color)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Replace match")
            }
        }
        .padding(.horizontal, Metrics.Space.regular)
        .padding(.vertical, 2)
        .background(
            isHovered
                ? theme.chrome.rowHover.color
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.row))
        .onHover { hovering in
            hoveredMatchID = hovering ? match.id : nil
        }
    }

    private func snippetView(for match: WorkspaceSearchMatch) -> some View {
        let line = match.lineContent
        let nsLine = line as NSString
        let range = match.matchRangeInLine

        if range.location != NSNotFound, range.location + range.length <= nsLine.length {
            let before = nsLine.substring(to: range.location)
            let matched = nsLine.substring(with: range)
            let after = nsLine.substring(from: range.location + range.length)

            return Text(before).foregroundColor(theme.text.color)
                + Text(matched).bold().foregroundColor(theme.chrome.accent.color)
                + Text(after).foregroundColor(theme.text.color)
        } else {
            return Text(line).foregroundColor(theme.text.color)
        }
    }

    private func directoryParent(for relativePath: String) -> String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    private func syncExpandedFiles() {
        for file in appState.workspaceSearchResults {
            expandedFileIDs.insert(file.id)
        }
    }

    private func toggleExpandCollapseAll() {
        if expandedFileIDs.count == appState.workspaceSearchResults.count {
            expandedFileIDs.removeAll()
        } else {
            for file in appState.workspaceSearchResults {
                expandedFileIDs.insert(file.id)
            }
        }
    }
}
