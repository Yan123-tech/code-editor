import Foundation
import Testing

@testable import CodeEditorLSP

// MARK: - Test helpers

/// Frames a JSON-RPC body with the `Content-Length` header the transport expects.
private func framed(_ json: String) -> Data {
    let body = Data(json.utf8)
    var data = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
    data.append(body)
    return data
}

/// A one-cell box so a `@Sendable` disconnection handler can signal back to the test.
private final class Flag: @unchecked Sendable {
    var value = false
}

/// Wait until the transport reports `count` parked requests, or fail after `timeout`.
private func waitForPending(
    _ transport: JSONRPCTransport,
    _ count: Int = 1,
    timeout: TimeInterval = 1.0
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await transport.testPendingIds.count >= count { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

// MARK: - Framing

@Suite("JSONRPCTransport framing")
struct JSONRPCTransportFramingTests {
    @Test("extracts a message once enough bytes have arrived")
    func completeFrame() {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"result":42}"#.utf8)
        var buffer = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        buffer.append(body)

        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == body)
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == nil)
    }

    @Test("waits for the body when only a header has arrived")
    func partialMessage() {
        var buffer = Data("Content-Length: 16\r\n\r\n".utf8)
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == nil)

        buffer.append(Data("partial".utf8))
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == nil)

        buffer.append(Data("body!more".utf8))
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == Data("partialbody!more".utf8))
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == nil)
    }

    @Test("reassembles a message split across two reads")
    func splitAcrossReads() {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"result":"ok"}"#.utf8)
        let header = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        var buffer = Data()

        buffer.append(header + body.prefix(5))
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == nil)
        buffer.append(body.dropFirst(5))
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == body)
    }

    @Test("extracts consecutive messages from one buffer")
    func twoMessagesOneRead() {
        let body1 = Data(#"{"jsonrpc":"2.0","id":1,"result":1}"#.utf8)
        let body2 = Data(#"{"jsonrpc":"2.0","id":2,"result":2}"#.utf8)
        var buffer = Data()
        buffer.append(Data("Content-Length: \(body1.count)\r\n\r\n".utf8))
        buffer.append(body1)
        buffer.append(Data("Content-Length: \(body2.count)\r\n\r\n".utf8))
        buffer.append(body2)

        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == body1)
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == body2)
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == nil)
    }

    @Test("resynchronizes past a malformed header")
    func malformedHeader() {
        let body = Data(#"{"a":1}"#.utf8)
        var buffer = Data()
        buffer.append(Data("GARBAGE_LINE_WITH_NO_LENGTH\r\n".utf8))
        buffer.append(Data("Content-Length: \(body.count)\r\n\r\n".utf8))
        buffer.append(body)

        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == body)
        #expect(JSONRPCTransport.parseNextMessage(from: &buffer) == nil)
    }
}

// MARK: - Response routing

@Suite("JSONRPCTransport response routing")
private struct ResponseRoutingTests {
    private func decode(_ json: String) throws -> RawMessage {
        try JSONDecoder().decode(RawMessage.self, from: Data(json.utf8))
    }

    @Test("a result resumes the parked request with the encoded value")
    func resultResumes() throws {
        let message = try decode(#"{"jsonrpc":"2.0","id":1,"result":"ok"}"#)
        switch JSONRPCTransport.routeResponse(message) {
        case .resume(let data):
            #expect(String(data: data, encoding: .utf8) == #""ok""#)
        default:
            Issue.record("expected a resume action")
        }
    }

    @Test("a null result resumes with null")
    func nullResultResumes() throws {
        let message = try decode(#"{"jsonrpc":"2.0","id":1,"result":null}"#)
        switch JSONRPCTransport.routeResponse(message) {
        case .resume(let data):
            #expect(String(data: data, encoding: .utf8) == "null")
        default:
            Issue.record("expected a resume action")
        }
    }

    @Test("an error envelope fails the request with the server's message")
    func errorEnvelopeFails() throws {
        let message = try decode(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"boom"}}"#)
        switch JSONRPCTransport.routeResponse(message) {
        case .failure(let error):
            if let responseError = error as? RawMessage.ResponseError {
                #expect(responseError.code == -32603)
                #expect(responseError.message == "boom")
            } else {
                Issue.record("expected a ResponseError")
            }
        default:
            Issue.record("expected a failure action")
        }
    }

    @Test("a notification (no id) is not routed to a parked request")
    func notificationIsNotAResponse() throws {
        let message = try decode(#"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{}}"#)
        switch JSONRPCTransport.routeResponse(message) {
        case .none:
            break
        default:
            Issue.record("a notification should not be routed as a response")
        }
    }
}

// MARK: - Round-trip and crash behaviour

@Suite("JSONRPCTransport process behaviour")
private struct ProcessBehaviourTests {
    @Test("a response resumes the parked request")
    func responseResumesRequest() async throws {
        let transport = JSONRPCTransport()
        await transport.startForTesting()

        let task = Task { try await transport.request(method: "m", params: nil) }
        await waitForPending(transport)

        await transport.ingest(framed(#"{"jsonrpc":"2.0","id":1,"result":"ok"}"#))
        let data = try await task.value
        #expect(String(data: data, encoding: .utf8) == #""ok""#)
    }

    @Test("a server error is surfaced instead of an opaque decode failure")
    func serverErrorThrows() async throws {
        let transport = JSONRPCTransport()
        await transport.startForTesting()

        let task = Task { try await transport.request(method: "m", params: nil) }
        await waitForPending(transport)

        await transport.ingest(framed(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"boom"}}"#))
        do {
            _ = try await task.value
            Issue.record("expected the request to throw")
        } catch let error as RawMessage.ResponseError {
            #expect(error.code == -32603)
            #expect(error.message == "boom")
        } catch {
            Issue.record("expected a ResponseError, got \(error)")
        }
    }

    @Test("a server exit fails in-flight requests and notifies the disconnection handler")
    func serverExitFailsRequests() async throws {
        let transport = JSONRPCTransport()
        await transport.startForTesting()

        let flag = Flag()
        await transport.setDisconnectionHandler { flag.value = true }

        let task = Task { try await transport.request(method: "m", params: nil) }
        await waitForPending(transport, 1)

        await transport.handleServerClosed()

        do {
            _ = try await task.value
            Issue.record("expected the request to throw")
        } catch {
            #expect(error is TransportError, "\(error) should be a TransportError")
        }
        #expect(flag.value)
        #expect(await transport.isConnected == false)
    }
}
