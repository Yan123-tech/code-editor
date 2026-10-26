import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - TerminalTransportError

public enum TerminalTransportError: LocalizedError, Sendable {
    case ptyAllocationFailed(Int32)
    case grantptFailed(Int32)
    case unlockptFailed(Int32)
    case ptsnameFailed
    case slaveOpenFailed(Int32)
    case processLaunchFailed(String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .ptyAllocationFailed(let code):
            return "Failed to allocate pseudo-terminal master (errno \(code))."
        case .grantptFailed(let code):
            return "Failed to grant pseudo-terminal permissions (errno \(code))."
        case .unlockptFailed(let code):
            return "Failed to unlock pseudo-terminal (errno \(code))."
        case .ptsnameFailed:
            return "Failed to resolve pseudo-terminal slave device name."
        case .slaveOpenFailed(let code):
            return "Failed to open pseudo-terminal slave (errno \(code))."
        case .processLaunchFailed(let msg):
            return "Failed to launch shell process: \(msg)"
        case .notConnected:
            return "Terminal transport is not connected."
        }
    }
}

// MARK: - TerminalTransport Protocol

/// Low-level transport abstraction for driving a subprocess via a PTY or fallback Pipes.
public protocol TerminalTransport: AnyObject, Sendable {
    var isRunning: Bool { get }

    func start(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        cols: Int,
        rows: Int,
        onOutput: @escaping @Sendable (Data) -> Void,
        onTermination: @escaping @Sendable (Int32) -> Void
    ) throws

    func write(_ data: Data) throws
    func resize(cols: Int, rows: Int)
    func sendInterrupt()
    func terminate()
}

// MARK: - PTYTerminalTransport

/// Drives a shell process via a real POSIX pseudo-terminal (PTY) on Darwin.
public final class PTYTerminalTransport: TerminalTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var masterFD: Int32 = -1
    private var masterHandle: FileHandle?

    public init() {}

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    public func start(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        cols: Int,
        rows: Int,
        onOutput: @escaping @Sendable (Data) -> Void,
        onTermination: @escaping @Sendable (Int32) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil else { return }

        // 1. Open master pseudo-terminal
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else {
            throw TerminalTransportError.ptyAllocationFailed(errno)
        }

        guard grantpt(master) == 0 else {
            close(master)
            throw TerminalTransportError.grantptFailed(errno)
        }

        guard unlockpt(master) == 0 else {
            close(master)
            throw TerminalTransportError.unlockptFailed(errno)
        }

        guard let slaveNamePtr = ptsname(master) else {
            close(master)
            throw TerminalTransportError.ptsnameFailed
        }

        let slavePath = String(cString: slaveNamePtr)
        let slave = open(slavePath, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            throw TerminalTransportError.slaveOpenFailed(errno)
        }

        // 2. Set initial terminal dimensions
        var ws = winsize()
        ws.ws_col = UInt16(max(10, cols))
        ws.ws_row = UInt16(max(5, rows))
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        _ = ioctl(master, TIOCSWINSZ, &ws)

        // 3. Configure subprocess
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        if let workingDirectory {
            proc.currentDirectoryURL = workingDirectory
        }

        var processEnv = environment
        if processEnv["TERM"] == nil {
            processEnv["TERM"] = "xterm-256color"
        }
        if processEnv["COLORTERM"] == nil {
            processEnv["COLORTERM"] = "truecolor"
        }
        proc.environment = processEnv

        // Wrap slave FD in FileHandle for the child process.
        // Once proc.run() executes, the child duplicates stdin/stdout/stderr.
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        do {
            try proc.run()
        } catch {
            close(master)
            throw TerminalTransportError.processLaunchFailed(error.localizedDescription)
        }

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        self.masterFD = master
        self.masterHandle = masterHandle
        self.process = proc

        // Read output from PTY master
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                onOutput(data)
            }
        }

        proc.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.lock.lock()
            self.masterHandle?.readabilityHandler = nil
            self.lock.unlock()
            onTermination(process.terminationStatus)
        }
    }

    public func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        guard masterFD >= 0, let masterHandle else {
            throw TerminalTransportError.notConnected
        }
        try masterHandle.write(contentsOf: data)
    }

    public func resize(cols: Int, rows: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard masterFD >= 0 else { return }
        var ws = winsize()
        ws.ws_col = UInt16(max(10, cols))
        ws.ws_row = UInt16(max(5, rows))
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    public func sendInterrupt() {
        lock.lock()
        defer { lock.unlock() }

        guard masterFD >= 0 else { return }
        // 1. Send ETX (0x03) character through terminal discipline
        _ = try? masterHandle?.write(contentsOf: Data([0x03]))

        // 2. Also signal the child process or foreground process group
        if let proc = process, proc.isRunning {
            let pgrp = tcgetpgrp(masterFD)
            if pgrp > 0 {
                kill(-pgrp, SIGINT)
            } else {
                kill(proc.processIdentifier, SIGINT)
            }
        }
    }

    public func terminate() {
        lock.lock()
        defer { lock.unlock() }

        masterHandle?.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        if masterFD >= 0 {
            try? masterHandle?.close()
            masterFD = -1
        }
        masterHandle = nil
        process = nil
    }
}

// MARK: - PipeTerminalTransport (Fallback)

/// Fallback transport using Foundation `Pipe()` when PTY allocation is unavailable.
public final class PipeTerminalTransport: TerminalTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?

    public init() {}

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    public func start(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        cols: Int,
        rows: Int,
        onOutput: @escaping @Sendable (Data) -> Void,
        onTermination: @escaping @Sendable (Int32) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        if let workingDirectory {
            proc.currentDirectoryURL = workingDirectory
        }
        proc.environment = environment

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = error

        do {
            try proc.run()
        } catch {
            throw TerminalTransportError.processLaunchFailed(error.localizedDescription)
        }

        self.process = proc
        self.inputHandle = input.fileHandleForWriting
        self.outputHandle = output.fileHandleForReading
        self.errorHandle = error.fileHandleForReading

        outputHandle?.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            onOutput(data)
        }

        errorHandle?.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            onOutput(data)
        }

        proc.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.lock.lock()
            self.outputHandle?.readabilityHandler = nil
            self.errorHandle?.readabilityHandler = nil
            self.lock.unlock()
            onTermination(process.terminationStatus)
        }
    }

    public func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let inputHandle else {
            throw TerminalTransportError.notConnected
        }
        try inputHandle.write(contentsOf: data)
    }

    public func resize(cols: Int, rows: Int) {
        // Pipes do not support window size ioctls
    }

    public func sendInterrupt() {
        lock.lock()
        defer { lock.unlock() }

        _ = try? inputHandle?.write(contentsOf: Data([0x03]))
        if let pid = process?.processIdentifier, pid > 0 {
            kill(pid, SIGINT)
        }
    }

    public func terminate() {
        lock.lock()
        defer { lock.unlock() }

        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        try? inputHandle?.close()
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
        process = nil
    }
}
