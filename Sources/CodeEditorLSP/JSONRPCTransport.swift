import Foundation

// MARK: - Transport errors

public enum TransportError: Error, LocalizedError {
    case notConnected
    case processLaunchFailed(String)
    case writeFailed(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "The language server process is not running."
        case .processLaunchFailed(let message):
            "Could not start the language server: \(message)"
        case .writeFailed(let message):
            "Could not write to the language server: \(message)"
        case .requestFailed(let message):
            message
        }
    }
}

// MARK: - JSONRPCTransport

/// Owns the language server subprocess and speaks LSP's `Content-Length` framing over pipes.
///
/// Reads are drained continuously on a background queue, accumulated into a buffer, and
/// split into complete messages. Every request is parked in a continuation until a
/// response with a matching id arrives.
public actor JSONRPCTransport {
    private var process: Process?
    private var writeHandle: FileHandle?
    private var readHandle: FileHandle?
    /// Held open by `startForTesting` so writes to the test pipe don't trip SIGPIPE.
    private var testPipe: Pipe?

    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var notificationHandlers: [@Sendable (String, JSONValue) -> Void] = []
    /// Called when the server process disappears (crash/exit). Lets the LSP client react — e.g.
    /// mark itself not-ready and clear the `lastError` so the editor can stop waiting on it.
    private var onDisconnection: (@Sendable () -> Void)?
    private var nextId = 1
    private var isRunning = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public var isConnected: Bool { isRunning }

    // MARK: - Process lifecycle

    public func start(_ command: [String], workingDirectory: URL? = nil) throws {
        guard !isRunning else { return }
        guard let executable = command.first else {
            throw TransportError.processLaunchFailed("empty command")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw TransportError.processLaunchFailed(error.localizedDescription)
        }

        self.process = process
        self.writeHandle = input.fileHandleForWriting
        self.readHandle = output.fileHandleForReading
        self.isRunning = true
        self.nextId = 1

        startReading()
    }

    public func stop() {
        readHandle?.readabilityHandler = nil
        readHandle?.closeFile()
        readHandle = nil
        try? writeHandle?.close()
        writeHandle = nil
        testPipe = nil

        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        isRunning = false
        buffer.removeAll()

        // Fail anything still waiting so callers don't hang forever.
        for (_, continuation) in pending {
            continuation.resume(throwing: TransportError.notConnected)
        }
        pending.removeAll()
    }

    // MARK: - Testing seam

    /// Drives a request/response cycle in tests without launching a real server.
    /// Sets the running flag and attaches a discarding write pipe so `request(...)` can
    /// park a continuation; tests then feed responses via `ingest` or simulate a crash
    /// via `handleServerClosed`.
    internal func startForTesting() {
        self.isRunning = true
        self.nextId = 1
        self.process = nil
        let pipe = Pipe()
        self.testPipe = pipe
        self.writeHandle = pipe.fileHandleForWriting
        self.readHandle = nil
    }

    /// The ids of requests currently waiting on a response. Used to wait for a parked
    /// request before feeding it a response in tests.
    internal var testPendingIds: [Int] { pending.keys.sorted() }

    // MARK: - Reading

    private func startReading() {
        readHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                Task { await self?.handleServerClosed() }
                return
            }
            Task { await self?.ingest(data) }
        }
    }

    private static let queueKey = DispatchSpecificKey<Void>()

    /// Append bytes and dispatch every complete framed message.
    internal func ingest(_ data: Data) {
        buffer.append(data)

        while let message = Self.parseNextMessage(from: &buffer) {
            handle(message)
        }
    }

    /// Extract the next `Content-Length`-framed message, or nil if more bytes are needed.
    ///
    /// Pure with respect to the actor: it only touches the supplied buffer, so it is
    /// unit-tested directly (including messages split across reads and malformed headers).
    internal static func parseNextMessage(from buffer: inout Data) -> Data? {
        let headerEnd = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        guard let headerEnd else { return nil }

        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        let header = String(decoding: headerData, as: UTF8.self)

        guard
            let length =
                header
                .split(separator: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("content-length:") })
                .flatMap({ Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) })
        else {
            // Malformed header; drop it and resynchronize on the next one.
            buffer.removeSubrange(buffer.startIndex...headerEnd.upperBound)
            return parseNextMessage(from: &buffer)
        }

        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else {
            return nil
        }

        let end = buffer.index(bodyStart, offsetBy: length)
        let body = Data(buffer[bodyStart..<end])
        buffer.removeSubrange(buffer.startIndex..<end)
        return body
    }

    private func handle(_ body: Data) {
        guard let message = try? decoder.decode(RawMessage.self, from: body) else { return }

        if let id = message.id {
            // A response to a request we sent.
            switch Self.routeResponse(message) {
            case .failure(let error):
                pending.removeValue(forKey: id)?.resume(throwing: error)
            case .resume(let value):
                pending.removeValue(forKey: id)?.resume(returning: value)
            case .none:
                // No response id to match against — should not happen here.
                break
            }
            return
        }

        if let method = message.method {
            let params = message.result ?? .null
            for handler in notificationHandlers {
                handler(method, params)
            }
        }
    }

    /// Decide what a parked request continuation resumes with for one decoded message.
    ///
    /// - A `result` resumes the caller with that value (JSON-encoded).
    /// - An `error` envelope resumes the caller **throwing** the server's `ResponseError`,
    ///   so the error message is surfaced instead of being silently turned into `null` and
    ///   later failing as an opaque decode error.
    ///
    /// Pure with respect to actor state: it does not read or write `pending`, so it is
    /// unit-tested directly.
    internal static func routeResponse(_ message: RawMessage) -> ResponseAction {
        guard message.id != nil else { return .none }
        if let error = message.error {
            return .failure(error)
        }
        let result = message.result.flatMap { try? responseEncoder.encode($0) }
        return .resume(result ?? Data("null".utf8))
    }

    internal enum ResponseAction {
        /// Resume the parked request with this data.
        case resume(Data)
        /// Resume the parked request throwing this error.
        case failure(Error)
        /// Not a response (e.g. a notification with no id).
        case none
    }

    private static let responseEncoder = JSONEncoder()

    /// Called when the server's read pipe reports EOF — i.e. the process exited, most
    /// likely a crash. Any in-flight request is failed with `notConnected` so callers do
    /// not hang, and `onDisconnection` lets the LSP client flip to not-ready.
    internal func handleServerClosed() {
        guard isRunning else { return }
        isRunning = false
        for (_, continuation) in pending {
            continuation.resume(throwing: TransportError.notConnected)
        }
        pending.removeAll()
        onDisconnection?()
    }

    // MARK: - Writing

    public func onNotification(_ handler: @escaping @Sendable (String, JSONValue) -> Void) {
        notificationHandlers.append(handler)
    }

    /// Register a callback fired when the server process exits unexpectedly (crash or clean
    /// exit detected via a closed read pipe). The LSP client uses this to flip to a
    /// not-ready state so callers fail fast instead of hanging.
    public func setDisconnectionHandler(_ handler: @escaping @Sendable () -> Void) {
        onDisconnection = handler
    }

    public func notify(method: String, params: (any Encodable)?) async throws {
        let payload = try encoder.encode(LSPNotification(method: method, params: params.map(AnyEncodable.init)))
        write(payload)
    }

    public func request(method: String, params: (any Encodable)?) async throws -> Data {
        guard isRunning else { throw TransportError.notConnected }

        let id = nextId
        nextId += 1

        let payload = try encoder.encode(LSPRequest(id: id, method: method, params: params.map(AnyEncodable.init)))

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { await self.write(payload) }
        }
    }

    /// Send a request and decode the `result` field.
    public func request<T: Decodable>(method: String, params: (any Encodable)?, as type: T.Type) async throws -> T {
        let data = try await request(method: method, params: params)
        return try decoder.decode(T.self, from: data)
    }

    private func write(_ payload: Data) {
        guard let writeHandle else {
            for (_, continuation) in pending {
                continuation.resume(throwing: TransportError.notConnected)
            }
            pending.removeAll()
            return
        }

        var framed = Data()
        framed.append(Data("Content-Length: \(payload.count)\r\n\r\n".utf8))
        framed.append(payload)

        do {
            try writeHandle.write(contentsOf: framed)
        } catch {
            let failure = TransportError.writeFailed(error.localizedDescription)
            for (_, continuation) in pending {
                continuation.resume(throwing: failure)
            }
            pending.removeAll()
        }
    }
}
