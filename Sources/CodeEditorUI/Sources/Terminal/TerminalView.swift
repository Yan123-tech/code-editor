import CodeEditorCore
import CodeEditorTerminal
import CodeEditorThemes
import SwiftUI

/// Terminal panel: a scrollback of output lines plus a command input.
public struct TerminalView: View {
    @Bindable var terminal: TerminalSession
    let theme: Theme

    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    public init(terminal: TerminalSession, theme: Theme) {
        self.terminal = terminal
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(terminal.outputLines) { line in
                            lineView(for: line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }

                        inputLine
                            .id(inputAnchor)
                    }
                    .padding(.horizontal, Metrics.Space.regular)
                    .padding(.vertical, Metrics.Space.compact)
                }
                .background(theme.chrome.panelBackground.color)
                .onChange(of: terminal.outputLines.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: terminal.activeLine?.text) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onTapGesture { isInputFocused = true }
            }
        }
        .frame(minHeight: 120)
        .background(theme.chrome.panelBackground.color)
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: TerminalSizePreferenceKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(TerminalSizePreferenceKey.self) { size in
            updateTerminalDimensions(size: size)
        }
        .onAppear {
            if !terminal.isConnected {
                terminal.connect()
            }
        }
        .focusedSceneValue(\.terminalFocus, isInputFocused)
        .focusedSceneValue(\.terminalInput, Binding(get: { input }, set: { input = $0 }))
        .focusedSceneValue(\.terminalSubmit, submit)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: Metrics.Space.regular) {
            Circle()
                .fill(
                    terminal.isConnected
                        ? theme.semantic.success.color
                        : theme.semantic.danger.color
                )
                .frame(width: 6, height: 6)
                .help(terminal.isConnected ? "Connected" : "Disconnected")

            Text("Terminal")
                .font(Typography.panelHeader)
                .foregroundStyle(theme.text.color)

            if let error = terminal.connectionError {
                Text(error)
                    .font(Typography.hint)
                    .foregroundStyle(theme.semantic.warning.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            headerButton("Interrupt", icon: "xmark.circle", help: "Send Ctrl-C (SIGINT)") {
                terminal.sendControlC()
            }
            .disabled(!terminal.isConnected)

            headerButton("Clear", icon: "trash", help: "Clear scrollback") {
                terminal.clear()
            }

            headerButton(
                terminal.isConnected ? "Restart" : "Connect",
                icon: "arrow.triangle.2.circlepath",
                help: terminal.isConnected ? "Restart the shell" : "Start the shell"
            ) {
                terminal.disconnect()
                terminal.connect()
            }
        }
        .padding(.horizontal, Metrics.Space.regular)
        .frame(height: Metrics.Height.panelHeader)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.chrome.border.color).frame(height: 1)
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if theme.chrome.usesMaterials {
            Rectangle().fill(.thinMaterial)
        } else {
            Rectangle().fill(theme.chrome.barBackground.color)
        }
    }

    private func headerButton(
        _ label: String,
        icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("\(label) — \(help)")
        .accessibilityLabel(label)
    }

    private var inputLine: some View {
        HStack(spacing: 0) {
            if let activeLine = terminal.activeLine,
                !activeLine.text.trimmingCharacters(in: .whitespaces).isEmpty
            {
                lineView(for: activeLine)
            } else {
                Text(terminal.workingDirectory.map { "\($0.lastPathComponent) " } ?? "")
                    .foregroundStyle(theme.secondaryText.color)
                Text("$ ")
                    .foregroundStyle(theme.chrome.accent.color)
            }
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .foregroundColor(theme.text.color)
                .focused($isInputFocused)
                .onSubmit(submit)
                .onExitCommand { input = "" }
                .onMoveCommand { direction in
                    switch direction {
                    case .up:
                        input = terminal.recallPrevious()
                    case .down:
                        input = terminal.recallNext()
                    default:
                        break
                    }
                }
        }
        .font(.system(size: 12, design: .monospaced))
    }

    private var inputAnchor: String { "terminal-input" }

    // MARK: - Line View

    @ViewBuilder
    private func lineView(for line: TerminalOutputLine) -> some View {
        if line.spans.isEmpty {
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(color(for: line.type))
        } else {
            styledText(for: line)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func styledText(for line: TerminalOutputLine) -> Text {
        line.spans.reduce(Text("")) { current, span in
            var spanText = Text(span.text)
            if let fg = span.style.foregroundColor {
                spanText = spanText.foregroundColor(
                    Color(red: fg.red, green: fg.green, blue: fg.blue, opacity: fg.alpha)
                )
            } else {
                spanText = spanText.foregroundColor(color(for: line.type))
            }

            if span.style.isBold {
                spanText = spanText.bold()
            }
            if span.style.isDim {
                spanText = spanText.foregroundStyle(.secondary)
            }
            if span.style.isItalic {
                spanText = spanText.italic()
            }
            if span.style.isUnderline {
                spanText = spanText.underline()
            }
            return current + spanText
        }
    }

    // MARK: - Actions

    private func submit() {
        let command = input
        input = ""
        terminal.submit(command)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard terminal.autoScroll else { return }
        withAnimation(.linear(duration: 0.05)) {
            proxy.scrollTo(inputAnchor, anchor: .bottom)
        }
    }

    private func color(for type: TerminalOutputType) -> Color {
        switch type {
        case .standard: theme.text.color
        case .errorOutput: theme.semantic.danger.color
        case .info: theme.secondaryText.color
        case .input: theme.chrome.accent.color
        }
    }

    private func updateTerminalDimensions(size: CGSize) {
        let charWidth: CGFloat = 7.2
        let lineHeight: CGFloat = 16.0

        let cols = max(10, Int(size.width / charWidth))
        let rows = max(5, Int(size.height / lineHeight))
        terminal.resize(cols: cols, rows: rows)
    }
}

// MARK: - PreferenceKey for Terminal Size

private struct TerminalSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

// MARK: - Focused values

struct TerminalFocusKey: FocusedValueKey {
    typealias Value = Bool
}

struct TerminalInputKey: FocusedValueKey {
    typealias Value = Binding<String>
}

struct TerminalSubmitKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var terminalFocus: Bool? {
        get { self[TerminalFocusKey.self] }
        set { self[TerminalFocusKey.self] = newValue }
    }

    var terminalInput: Binding<String>? {
        get { self[TerminalInputKey.self] }
        set { self[TerminalInputKey.self] = newValue }
    }

    var terminalSubmit: (() -> Void)? {
        get { self[TerminalSubmitKey.self] }
        set { self[TerminalSubmitKey.self] = newValue }
    }
}
