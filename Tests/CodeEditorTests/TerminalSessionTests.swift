import Foundation
import Testing
import os

@testable import CodeEditorTerminal

// MARK: - TerminalSessionTests

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

// MARK: - ANSITerminalParserTests

@Suite("ANSITerminalParser")
struct ANSITerminalParserTests {
    @Test("parses basic newlines into discrete lines")
    func newlineSplitting() {
        let parser = ANSITerminalParser()
        let data = Data("Line 1\nLine 2\nLine 3\n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 3)
        #expect(lines[0].text == "Line 1")
        #expect(lines[1].text == "Line 2")
        #expect(lines[2].text == "Line 3")
    }

    @Test("carriage return overwrites cells on the active line")
    func carriageReturnOverwrite() {
        let parser = ANSITerminalParser()
        let data = Data("Downloading 10%\rDownloading 50%\rDownloading 100%\n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 1)
        #expect(lines[0].text == "Downloading 100%")
    }

    @Test("backspace moves cursor backward")
    func backspaceHandling() {
        let parser = ANSITerminalParser()
        let data = Data("abc\u{08}d\n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 1)
        #expect(lines[0].text == "abd")
    }

    @Test("tab expands to 8-space tab stops")
    func tabExpansion() {
        let parser = ANSITerminalParser()
        let data = Data("a\tb\n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 1)
        // 'a' at col 0, tab advances to col 8, 'b' placed at col 8
        #expect(lines[0].text == "a       b")
    }

    @Test("parses SGR bold and standard foreground colors")
    func sgrColorsAndStyles() {
        let parser = ANSITerminalParser()
        let data = Data("\u{1B}[1;31mError\u{1B}[0m: failed\n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 1)
        #expect(lines[0].text == "Error: failed")
        #expect(lines[0].spans.count == 2)

        let span1 = lines[0].spans[0]
        #expect(span1.text == "Error")
        #expect(span1.style.isBold == true)
        #expect(span1.style.foregroundColor == .red)

        let span2 = lines[0].spans[1]
        #expect(span2.text == ": failed")
        #expect(span2.style.isBold == false)
        #expect(span2.style.foregroundColor == nil)
    }

    @Test("parses 256-color and 24-bit RGB truecolor escape sequences")
    func extendedColors() {
        let parser = ANSITerminalParser()
        // 38;5;1 -> red, 38;2;128;64;32 -> RGB truecolor
        let data = Data("\u{1B}[38;5;1mRed256\u{1B}[0m \u{1B}[38;2;128;64;32mTrueColor\u{1B}[0m\n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 1)
        #expect(lines[0].text == "Red256 TrueColor")
        #expect(lines[0].spans.count == 3)

        #expect(lines[0].spans[0].style.foregroundColor == .red)
        let rgb = lines[0].spans[2].style.foregroundColor
        #expect(rgb != nil)
        #expect(abs((rgb?.red ?? 0) - 128.0 / 255.0) < 0.01)
        #expect(abs((rgb?.green ?? 0) - 64.0 / 255.0) < 0.01)
        #expect(abs((rgb?.blue ?? 0) - 32.0 / 255.0) < 0.01)
    }

    @Test("parses erase in line (CSI K)")
    func eraseInLine() {
        let parser = ANSITerminalParser()
        // Write text, \r to go to start, erase line with 2K, write new text
        let data = Data("Old Line Content\r\u{1B}[2KFresh Line\n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 1)
        #expect(lines[0].text == "Fresh Line")
    }

    @Test("handles escape sequences split across feed calls")
    func fragmentedSequences() {
        let parser = ANSITerminalParser()
        let chunk1 = Data("Hello \u{1B}[3".utf8)
        let chunk2 = Data("2mGreen\u{1B}[0m\n".utf8)

        let lines1 = parser.feed(chunk1)
        #expect(lines1.isEmpty)

        let lines2 = parser.feed(chunk2)
        #expect(lines2.count == 1)
        #expect(lines2[0].text == "Hello Green")
        #expect(lines2[0].spans.count == 2)
        #expect(lines2[0].spans[1].style.foregroundColor == .green)
    }

    @Test("flush outputs trailing line without newline")
    func flushTrailingBuffer() {
        let parser = ANSITerminalParser()
        let data = Data("Partial output without newline".utf8)
        let immediateLines = parser.feed(data)
        #expect(immediateLines.isEmpty)

        let flushed = parser.flush()
        #expect(flushed.count == 1)
        #expect(flushed[0].text == "Partial output without newline")
    }

    @Test("exposes uncommitted prompt in activeLine")
    func uncommittedActiveLine() {
        let parser = ANSITerminalParser()
        let data = Data("user@mac % ".utf8)
        let immediateLines = parser.feed(data)
        #expect(immediateLines.isEmpty)

        let active = parser.currentActiveLine()
        #expect(active != nil)
        #expect(active?.text == "user@mac % ")
    }

    @Test("trims trailing unstyled spaces from line on newline")
    func trailingWhitespaceTrim() {
        let parser = ANSITerminalParser()
        let data = Data("Hello World     \n".utf8)
        let lines = parser.feed(data)

        #expect(lines.count == 1)
        #expect(lines[0].text == "Hello World")
    }

    @Test("zsh prompt formatting and inline command overwrite")
    func zshPromptAndEcho() {
        let parser = ANSITerminalParser()
        // Simulate zsh PROMPT_EOL_MARK and prompt
        let bootData = Data(
            "%                                                                              \r \r\ryan@mac Code Editor % \u{1B}[?2004h"
                .utf8)
        let bootLines = parser.feed(bootData)
        #expect(bootLines.isEmpty)
        #expect(parser.currentActiveLine()?.text == "yan@mac Code Editor % ")

        // Simulate user command echo and output
        let echoData = Data("echo hi\u{1B}[?2004l\r\r\nhi\r\n".utf8)
        let lines = parser.feed(echoData)
        #expect(lines.count == 2)
        #expect(lines[0].text == "yan@mac Code Editor % echo hi")
        #expect(lines[1].text == "hi")
        #expect(parser.currentActiveLine() == nil)
    }
}

// MARK: - PTYTerminalTransportTests

@Suite("PTYTerminalTransport")
struct PTYTerminalTransportTests {
    @Test("spawns child process in a genuine TTY")
    func genuineTTYSession() async throws {
        let transport = PTYTerminalTransport()
        let shURL = URL(fileURLWithPath: "/bin/sh")

        let outputBox = OSAllocatedUnfairLock(initialState: Data())
        let exitedBox = OSAllocatedUnfairLock(initialState: false)

        try transport.start(
            executableURL: shURL,
            arguments: ["-c", "test -t 0 && test -t 1 && echo IS_A_REAL_PTY"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            cols: 80,
            rows: 24,
            onOutput: { data in
                outputBox.withLock { $0.append(data) }
            },
            onTermination: { _ in
                exitedBox.withLock { $0 = true }
            }
        )

        // Wait up to 3 seconds for subprocess to execute and finish
        let start = Date()
        while Date().timeIntervalSince(start) < 3.0 {
            let exited = exitedBox.withLock { $0 }
            if exited { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let outputData = outputBox.withLock { $0 }
        let outputString = String(decoding: outputData, as: UTF8.self)
        #expect(outputString.contains("IS_A_REAL_PTY"))
    }

    @Test("interactive shell executes command with carriage return")
    func interactiveShellExecution() async throws {
        let transport = PTYTerminalTransport()
        let shURL = URL(fileURLWithPath: "/bin/sh")

        let outputBox = OSAllocatedUnfairLock(initialState: Data())

        try transport.start(
            executableURL: shURL,
            arguments: ["-i"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            cols: 80,
            rows: 24,
            onOutput: { data in
                outputBox.withLock { $0.append(data) }
            },
            onTermination: { _ in }
        )

        // Wait a moment for shell initialization
        try await Task.sleep(nanoseconds: 100_000_000)

        // Submit command with carriage return (\r)
        try transport.write(Data("echo PTY_INTERACTIVE_OK\r".utf8))

        // Wait up to 3 seconds for output to appear
        let start = Date()
        var matched = false
        while Date().timeIntervalSince(start) < 3.0 {
            let outString = outputBox.withLock { String(decoding: $0, as: UTF8.self) }
            if outString.contains("PTY_INTERACTIVE_OK") {
                matched = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        transport.terminate()
        #expect(matched)
    }

    @Test("resizes window dimensions without error")
    func windowResize() throws {
        let transport = PTYTerminalTransport()
        let shURL = URL(fileURLWithPath: "/bin/sh")

        try transport.start(
            executableURL: shURL,
            arguments: ["-c", "sleep 1"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            cols: 80,
            rows: 24,
            onOutput: { _ in },
            onTermination: { _ in }
        )

        transport.resize(cols: 120, rows: 40)
        #expect(transport.isRunning)
        transport.terminate()
        #expect(!transport.isRunning)
    }
}
