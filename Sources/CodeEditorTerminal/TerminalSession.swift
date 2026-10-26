import Foundation

#if canImport(Darwin)
    import Darwin
#endif

// MARK: - TerminalSession

/// Runs a shell in a subprocess via a PTY (with Pipe fallback) and streams ANSI-parsed lines.
@MainActor
@Observable
public final class TerminalSession {
    // State
    public private(set) var isConnected = false
    public private(set) var connectionError: String?
    public private(set) var outputLines: [TerminalOutputLine] = []
    public private(set) var activeLine: TerminalOutputLine?
    public private(set) var currentInput = ""
    public var autoScroll = true

    /// Recently submitted commands, most recent last.
    public private(set) var history: [String] = []
    private var historyIndex: Int?
    private var pendingCommandEcho: String?

    // Configuration
    public var shellPath: String
    public var workingDirectory: URL?
    public var projectRootDirectory: URL?
    public var environment: [String: String]
    @ObservationIgnored public private(set) var cols: Int = 80
    @ObservationIgnored public private(set) var rows: Int = 24

    // Plumbing
    private var transport: TerminalTransport?
    private let parser: TerminalParser
    private let maxLines = 2000
    private var resizeTask: Task<Void, Never>?
    private var lastWorkingDirRefresh = Date.distantPast

    public init(
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        workingDirectory: URL? = nil,
        projectRootDirectory: URL? = nil,
        parser: TerminalParser = ANSITerminalParser()
    ) {
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        self.projectRootDirectory = projectRootDirectory ?? workingDirectory
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
        resizeTask?.cancel()
        resizeTask = nil

        guard let currentTransport = transport else { return }
        currentTransport.terminate()
        transport = nil

        let remaining = parser.flush(as: .standard)
        for line in remaining {
            appendLine(line)
        }
        activeLine = nil
        pendingCommandEcho = nil
        parser.reset()
        isConnected = false
    }

    private func handleIncomingData(_ data: Data) {
        refreshWorkingDirectory()
        let lines = parser.feed(data, as: .standard)
        for line in lines {
            if let pending = pendingCommandEcho,
                line.text.contains(pending)
            {
                pendingCommandEcho = nil
                appendLine(TerminalOutputLine(text: "\(promptPrefix)$ \(pending)", type: .input))
            } else {
                appendLine(line)
            }
        }
        activeLine = parser.currentActiveLine(as: .standard)
    }

    private func handleTermination(_ status: Int32) {
        let remaining = parser.flush(as: Self.outputType(for: status))
        for line in remaining {
            appendLine(line)
        }
        activeLine = nil
        pendingCommandEcho = nil
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
        if !isConnected {
            connect()
        }

        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            if transport is PTYTerminalTransport {
                pendingCommandEcho = nil
                appendLine(TerminalOutputLine(text: "\(promptPrefix)$", type: .input))
                write("\r")
            }
            return
        }

        if history.last != trimmed {
            history.append(trimmed)
        }
        historyIndex = nil

        if transport is PipeTerminalTransport {
            appendLine(TerminalOutputLine(text: "\(promptPrefix)$ \(trimmed)", type: .input))
            write(trimmed + "\n")
        } else {
            pendingCommandEcho = trimmed
            write(trimmed + "\r")
        }
        refreshWorkingDirectory(force: true)
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
        if !currentInput.isEmpty {
            appendLine(TerminalOutputLine(text: "\(promptPrefix)$ \(currentInput)^C", type: .input))
        } else {
            appendLine(TerminalOutputLine(text: "^C", type: .info))
        }
        currentInput = ""
        historyIndex = nil
        pendingCommandEcho = nil
        transport?.sendInterrupt()
    }

    public func resize(cols: Int, rows: Int, immediate: Bool = false) {
        self.cols = cols
        self.rows = rows

        resizeTask?.cancel()
        if immediate {
            transport?.resize(cols: cols, rows: rows)
        } else {
            resizeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, let self else { return }
                self.transport?.resize(cols: cols, rows: rows)
            }
        }
    }

    public func refreshWorkingDirectory(force: Bool = false) {
        #if canImport(Darwin)
            let now = Date()
            guard force || now.timeIntervalSince(lastWorkingDirRefresh) >= 0.5 else { return }
            lastWorkingDirRefresh = now

            guard let pid = transport?.processIdentifier, pid > 0 else { return }
            var vpi = proc_vnodepathinfo()
            let size = proc_pidinfo(
                pid,
                PROC_PIDVNODEPATHINFO,
                0,
                &vpi,
                Int32(MemoryLayout<proc_vnodepathinfo>.size)
            )
            guard size == MemoryLayout<proc_vnodepathinfo>.size else { return }
            let path = withUnsafePointer(to: &vpi.pvi_cdir.vip_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cstr in
                    String(cString: cstr)
                }
            }
            guard !path.isEmpty else { return }
            let newURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let currentURL = workingDirectory?.standardizedFileURL.resolvingSymlinksInPath()
            if currentURL?.path != newURL.path {
                workingDirectory = newURL
            }
        #endif
    }

    public var formattedPromptPath: String {
        Self.compactPath(currentURL: workingDirectory, rootURL: projectRootDirectory)
    }

    public static func compactPath(currentURL: URL?, rootURL: URL?) -> String {
        guard let currentURL else { return "" }
        let currentStandard = currentURL.standardizedFileURL.resolvingSymlinksInPath()

        if let rootURL {
            let rootStandard = rootURL.standardizedFileURL.resolvingSymlinksInPath()
            let rootName =
                rootStandard.lastPathComponent.isEmpty ? "project" : rootStandard.lastPathComponent

            if currentStandard.path == rootStandard.path {
                return rootName
            }

            let rootPrefix =
                rootStandard.path.hasSuffix("/") ? rootStandard.path : rootStandard.path + "/"
            if currentStandard.path.hasPrefix(rootPrefix) {
                let relative = String(currentStandard.path.dropFirst(rootPrefix.count))
                let components = relative.split(separator: "/").map { String($0) }
                if components.count <= 2 {
                    return "\(rootName)/\(components.joined(separator: "/"))"
                } else {
                    return "\(rootName)/…/\(components.last!)"
                }
            }
        }

        // Outside rootURL: check if within user's home directory
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            .resolvingSymlinksInPath().path
        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"

        if currentStandard.path == homePath {
            return "~"
        } else if currentStandard.path.hasPrefix(homePrefix) {
            let relative = String(currentStandard.path.dropFirst(homePrefix.count))
            let components = relative.split(separator: "/").map { String($0) }
            if components.count <= 2 {
                return "~/\(components.joined(separator: "/"))"
            } else {
                return "~/…/\(components.last!)"
            }
        }

        // System/other directory
        let components = currentStandard.path.split(separator: "/").map { String($0) }
        if components.count <= 2 {
            return currentStandard.path
        } else {
            return "/…/\(components.last ?? "")"
        }
    }

    private var promptPrefix: String {
        let path = formattedPromptPath
        return path.isEmpty ? "" : "\(path) "
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
        activeLine = nil
        pendingCommandEcho = nil
        parser.reset()
    }

    /// Append a line of output. Exposed for tests that do not spawn a real shell.
    public func appendForTesting(_ type: TerminalOutputType, _ text: String) {
        appendLine(TerminalOutputLine(text: text, type: type))
    }

    private func appendLine(_ line: TerminalOutputLine) {
        outputLines.append(line)
        if outputLines.count > maxLines {
            outputLines.removeFirst(outputLines.count - maxLines)
        }
    }
}
