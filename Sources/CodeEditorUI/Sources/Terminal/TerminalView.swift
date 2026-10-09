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
            Divider().overlay(theme.chrome.border.color)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(terminal.outputLines) { line in
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(color(for: line.type))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }

                        inputLine
                            .id(inputAnchor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(theme.background.color)
                .onChange(of: terminal.outputLines.count) { _, _ in
                    guard terminal.autoScroll else { return }
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo(inputAnchor, anchor: .bottom)
                    }
                }
                .onTapGesture { isInputFocused = true }
            }

            Divider().overlay(theme.chrome.border.color)
        }
        .frame(minHeight: 120, idealHeight: 200)
        .background(theme.background.color)
        .focusedSceneValue(\.terminalFocus, isInputFocused)
        .focusedSceneValue(\.terminalInput, Binding(get: { input }, set: { input = $0 }))
        .focusedSceneValue(\.terminalSubmit, submit)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 6) {
            Text("Terminal")
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.text.color)

            Circle()
                .fill(terminal.isConnected ? theme.semantic.success.color : theme.semantic.danger.color)
                .frame(width: 6, height: 6)

            if let error = terminal.connectionError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(theme.comment.color)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("Clear") { terminal.clear() }
                .controlSize(.small)

            Button(terminal.isConnected ? "Restart" : "Connect") {
                terminal.disconnect()
                terminal.connect()
            }
            .controlSize(.small)
            .disabled(terminal.isConnected)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private var inputLine: some View {
        HStack(spacing: 0) {
            Text("$ ")
                .foregroundColor(theme.chrome.accent.color)
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .foregroundColor(theme.text.color)
                .focused($isInputFocused)
                .onSubmit(submit)
                .onExitCommand { input = "" }
        }
        .font(.system(size: 12, design: .monospaced))
    }

    private var inputAnchor: String { "terminal-input" }

    // MARK: - Actions

    private func submit() {
        let command = input
        input = ""
        terminal.submit(command)
    }

    private func color(for type: TerminalOutputType) -> Color {
        switch type {
        case .standard: theme.text.color
        case .errorOutput: theme.semantic.danger.color
        case .info: theme.comment.color
        case .input: theme.string.color
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
