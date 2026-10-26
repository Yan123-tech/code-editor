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
    var processIdentifier: Int32? { get }

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

    public var processIdentifier: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return process?.processIdentifier
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

        // 2. Grant permissions & unlock slave
        guard grantpt(master) == 0 else {
            close(master)
            throw TerminalTransportError.grantptFailed(errno)
        }
        guard unlockpt(master) == 0 else {
            close(master)
            throw TerminalTransportError.unlockptFailed(errno)
        }

        // 3. Obtain slave path
        guard let slavePathPtr = ptsname(master) else {
            close(master)
            throw TerminalTransportError.ptsnameFailed
        }
        let slavePath = String(cString: slavePathPtr)

        // 4. Open slave descriptor
        let slave = open(slavePath, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            throw TerminalTransportError.slaveOpenFailed(errno)
        }

        // 5. Initial window size
        var ws = winsize()
        ws.ws_col = UInt16(max(10, cols))
        ws.ws_row = UInt16(max(5, rows))
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        _ = ioctl(master, TIOCSWINSZ, &ws)

        masterFD = master
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        self.masterHandle = masterHandle

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        var env = environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        proc.environment = env

        if let workingDirectory {
            proc.currentDirectoryURL = workingDirectory
        }

        proc.terminationHandler = { [weak self] p in
            self?.handleProcessTermination()
            onTermination(p.terminationStatus)
        }

        do {
            try proc.run()
        } catch {
            close(master)
            close(slave)
            masterFD = -1
            self.masterHandle = nil
            throw TerminalTransportError.processLaunchFailed(error.localizedDescription)
        }

        // In Darwin, closing the parent's copy of the slave descriptor post-spawn
        // ensures EOF is reliably delivered to the master when the child process exits.
        try? slaveHandle.close()

        self.process = proc

        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                self?.handleProcessTermination()
                return
            }
            onOutput(data)
        }
    }

    private func handleProcessTermination() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        masterHandle?.readabilityHandler = nil
        lock.unlock()
    }

    public func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let handle = masterHandle else {
            throw TerminalTransportError.notConnected
        }
        try handle.write(contentsOf: data)
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

    public var processIdentifier: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return process?.processIdentifier
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

        proc.terminationHandler = { p in
            onTermination(p.terminationStatus)
        }

        try proc.run()
        self.process = proc
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
        // Pipes do not have window size attributes
    }

    public func sendInterrupt() {
        lock.lock()
        defer { lock.unlock() }

        if let proc = process, proc.isRunning {
            proc.interrupt()
        }
    }

    public func terminate() {
        lock.lock()
        defer { lock.unlock() }

        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        process?.terminate()
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
        process = nil
    }
}
