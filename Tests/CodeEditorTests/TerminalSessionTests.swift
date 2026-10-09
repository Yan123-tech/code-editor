import Foundation
import Testing
@testable import CodeEditorTerminal

@MainActor
@Suite("TerminalSession")
struct TerminalSessionTests {
    @Test("records submitted commands in history")
    func historyRecording() async {
        let session = TerminalSession(shellPath: "/nonexistent-shell")

        session.appendForTesting(.input, "$ echo one")
        session.submit("echo one")
        session.submit("echo two")

        #expect(session.history == ["echo one", "echo two"])
    }

    @Test("walks back and forward through history")
    func historyRecall() {
        let session = TerminalSession(shellPath: "/nonexistent-shell")
        session.appendForTesting(.input, "a")
        session.submit("a")
        session.submit("b")

        #expect(session.recallPrevious() == "b")
        #expect(session.recallPrevious() == "a")
        #expect(session.recallNext() == "b")
        #expect(session.recallNext() == "")
    }

    @Test("does not connect to a missing shell")
    func failedConnect() {
        let session = TerminalSession(shellPath: "/nonexistent-shell")
        session.connect()

        #expect(!session.isConnected)
        #expect(session.connectionError != nil)
    }

    @Test("clearing removes all output")
    func clear() {
        let session = TerminalSession(shellPath: "/nonexistent-shell")
        session.appendForTesting(.standard, "output")
        #expect(!session.outputLines.isEmpty)

        session.clear()
        #expect(session.outputLines.isEmpty)
    }
}