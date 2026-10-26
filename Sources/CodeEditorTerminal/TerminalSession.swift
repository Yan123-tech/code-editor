import Foundation

// MARK: - TerminalSession

/// Runs an interactive shell inside a pseudo-terminal (PTY) or fallback pipes,
/// parsing ANSI escape sequences and streaming styled lines of output.
@MainActor
@Observable
public final class TerminalSession {
    // State
    public private(set) var isConnected = false
    public private(set) var connectionError: String?
    public private(set) var outputLines: [TerminalOutputLine] = []
    public private(set) var currentInput = ""
    public var autoScroll = true

    /// Recently submitted commands, most recent last.
    public private(set) var history: [String] = []
    private var historyIndex: Int?

    // Configuration
    public var shellPath: String
    public var workingDirectory: URL?
    public var environment: [String: String]
    public var cols: Int = 80
    public var rows: Int = 24

    // Plumbing
    private var transport: TerminalTransport?
    private let parser: TerminalParser
    private let maxLines = 2000

    public init(
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        workingDirectory: URL? = nil,
        parser: TerminalParser = ANSITerminalParser()
    ) {
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        self.environment = [:]
        self.parser = parser
    }

    // MARK: - Lifecycle

    public func connect() {
        guard transport == nil else { return }

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = [
            "\(home)/go/bin",
            "/usr/local/go/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        let newPath = (extraPaths + [currentPath]).filter { !$0.isEmpty }.joined(separator: ":")
        env["PATH"] = newPath
        for (key, value) in self.environment {
            env[key] = value
        }

        let executableURL = URL(fileURLWithPath: shellPath)
        let arguments = ["-i"]

        // Attempt PTY first; fallback to Pipe if PTY allocation fails
        let ptyTransport = PTYTerminalTransport()
        do {
            try ptyTransport.start(
                executableURL: executableURL,
                arguments: arguments,
                environment: env,
                workingDirectory: workingDirectory,
                cols: cols,
                rows: rows,
                onOutput: { [weak self] data in
                    Task { @MainActor [weak self] in
                        self?.handleIncomingData(data)
                    }
                },
                onTermination: { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.handleTermination(status)
                    }
                }
            )
            self.transport = ptyTransport
            self.isConnected = true
            self.connectionError = nil
        } catch {
            // PTY failed, try Pipe fallback
            let pipeTransport = PipeTerminalTransport()
            do {
                try pipeTransport.start(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: env,
                    workingDirectory: workingDirectory,
                    cols: cols,
                    rows: rows,
                    onOutput: { [weak self] data in
                        Task { @MainActor [weak self] in
                            self?.handleIncomingData(data)
                        }
                    },
                    onTermination: { [weak self] status in
                        Task { @MainActor [weak self] in
                            self?.handleTermination(status)
                        }
                    }
                )
                self.transport = pipeTransport
                self.isConnected = true
                self.connectionError = nil
            } catch {
                self.connectionError = error.localizedDescription
                self.isConnected = false
            }
        }
    }

    public func disconnect() {
        guard let currentTransport = transport else { return }
        currentTransport.terminate()
        transport = nil

        let remaining = parser.flush(as: .standard)
        for line in remaining {
            appendLine(line)
        }
        parser.reset()
        isConnected = false
    }

    private func handleIncomingData(_ data: Data) {
        let lines = parser.feed(data, as: .standard)
        for line in lines {
            appendLine(line)
        }
    }

    private func handleTermination(_ status: Int32) {
        let remaining = parser.flush(as: Self.outputType(for: status))
        for line in remaining {
            appendLine(line)
        }
        parser.reset()

        if status != 0 && status != SIGTERM {
            connectionError = "Shell exited with status \(status)"
        }
        appendLine(
            TerminalOutputLine(text: "[process exited]", type: Self.outputType(for: status))
        )
        transport = nil
        isConnected = false
    }

    private static func outputType(for status: Int32) -> TerminalOutputType {
        (status == 0 || status == SIGTERM) ? .standard : .errorOutput
    }

    // MARK: - Input

    public func submit(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if history.last != trimmed {
            history.append(trimmed)
        }
        historyIndex = nil

        // If using pipe transport, manually echo input line
        if transport is PipeTerminalTransport {
            appendLine(TerminalOutputLine(text: "$ \(trimmed)", type: .input))
        }

        write(trimmed + "\n")
    }

    public func setInput(_ input: String) {
        currentInput = input
    }

    /// Walk back through command history; returns the input to display.
    public func recallPrevious() -> String {
        guard !history.isEmpty else { return currentInput }
        let index = historyIndex.map { max(0, $0 - 1) } ?? history.count - 1
        historyIndex = index
        currentInput = history[index]
        return currentInput
    }

    public func recallNext() -> String {
        guard !history.isEmpty, let index = historyIndex else { return currentInput }
        if index >= history.count - 1 {
            historyIndex = nil
            currentInput = ""
            return currentInput
        }
        historyIndex = index + 1
        currentInput = history[index + 1]
        return currentInput
    }

    public func sendControlC() {
        transport?.sendInterrupt()
    }

    public func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        transport?.resize(cols: cols, rows: rows)
    }

    private func write(_ string: String) {
        guard let transport else {
            connectionError = "Not connected to a shell."
            return
        }
        do {
            try transport.write(Data(string.utf8))
        } catch {
            connectionError = error.localizedDescription
        }
    }

    // MARK: - Output

    public func clear() {
        outputLines.removeAll()
        parser.reset()
    }

    /// Append a line of output. Exposed for tests that do not spawn a real shell.
    public func appendForTesting(_ type: TerminalOutputType, _ text: String) {
        appendLine(TerminalOutputLine(text: text, type: type))
    }

    private func appendLine(_ line: TerminalOutputLine) {
        let trimmed = line.text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        outputLines.append(line)
        if outputLines.count > maxLines {
            outputLines.removeFirst(outputLines.count - maxLines)
        }
    }
}
