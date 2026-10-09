import Foundation

// MARK: - TerminalOutputType

/// Types of terminal output, used for coloring.
public enum TerminalOutputType: Sendable {
    case standard
    case errorOutput
    case info
    case input
}

// MARK: - TerminalOutputLine

/// A single line of terminal output.
public struct TerminalOutputLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let type: TerminalOutputType

    public init(id: UUID = UUID(), text: String, type: TerminalOutputType) {
        self.id = id
        self.text = text
        self.type = type
    }
}

// MARK: - TerminalSession

/// Runs a shell in a subprocess and streams its output as lines of text.
///
/// Note: this drives the shell over pipes rather than a PTY, so it behaves like a
/// pipe-driven shell (no job control, no terminal echo). Input is echoed locally.
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

    // Subprocess plumbing
    private var process: Process?
    private var inputHandle: FileHandle?
    private var buffer = Data()

    private let maxLines = 2000

    public init(
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        workingDirectory: URL? = nil
    ) {
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        self.environment = [:]
    }

    // MARK: - Lifecycle

    public func connect() {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-i"]
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in self.environment {
            environment[key] = value
        }
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
            return
        }

        self.process = process
        self.inputHandle = input.fileHandleForWriting
        isConnected = true
        connectionError = nil

        read(output.fileHandleForReading, as: .standard)
        read(error.fileHandleForReading, as: .errorOutput)
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.handleTermination(finished.terminationStatus)
            }
        }
    }

    public func disconnect() {
        guard let process else { return }
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        try? inputHandle?.close()
        inputHandle = nil
        self.process = nil
        buffer.removeAll()
        isConnected = false
    }

    private func handleTermination(_ status: Int32) {
        if status != 0 && status != SIGTERM {
            connectionError = "Shell exited with status \(status)"
        }
        outputLines.append(
            TerminalOutputLine(text: "[process exited]", type: Self.outputType(for: status))
        )
        process = nil
        inputHandle = nil
        isConnected = false
    }

    private static func outputType(for status: Int32) -> TerminalOutputType {
        (status == 0 || status == SIGTERM) ? .standard : .errorOutput
    }

    // MARK: - Input

    public func submit(_ command: String) {
        let command = command.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }

        if history.last != command { history.append(command) }
        historyIndex = nil
        append(.input, "$ \(command)")
        write(command + "\n")
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
        write("\u{03}")
    }

    private func write(_ string: String) {
        guard let inputHandle else {
            connectionError = "Not connected to a shell."
            return
        }
        do {
            try inputHandle.write(contentsOf: Data(string.utf8))
        } catch {
            connectionError = error.localizedDescription
        }
    }

    // MARK: - Output

    public func clear() {
        outputLines.removeAll()
    }

    /// Append a line of output. Exposed for tests that do not spawn a real shell.
    public func appendForTesting(_ type: TerminalOutputType, _ text: String) {
        append(type, text)
    }

    private func read(_ handle: FileHandle, as type: TerminalOutputType) {
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            Task { @MainActor [weak self] in
                self?.ingest(data, as: type)
            }
        }
    }

    private func ingest(_ data: Data, as type: TerminalOutputType) {
        buffer.append(data)
        // Keep only the trailing partial line; complete lines are flushed below.
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = buffer[buffer.index(after: newlineIndex)...]
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .newlines)
            append(type, line)
        }

        // Guard against a runaway stream with no newlines.
        if buffer.count > 1 << 20 {
            let flushed = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            append(type, flushed)
        }
    }

    private func append(_ type: TerminalOutputType, _ text: String) {
        let line = text.trimmingCharacters(in: .newlines)
        guard !line.isEmpty else { return }
        outputLines.append(TerminalOutputLine(text: line, type: type))
        if outputLines.count > maxLines {
            outputLines.removeFirst(outputLines.count - maxLines)
        }
    }
}
