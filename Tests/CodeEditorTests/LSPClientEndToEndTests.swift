import Foundation
import Testing

@testable import CodeEditorLSP

/// End-to-end against a running `sourcekit-lsp`, using a throwaway single-file Swift
/// document as the workspace. Local validation only — not run in CI (CI has no Swift 6.4
/// toolchain and can't launch `sourcekit-lsp`; see docs/MEMORY.md #1).
///
/// `sourcekit-lsp` is a heavy, occasionally-flaky process in this sandbox: it can crash
/// during `initialize` or stall mid-`completion` under `swift test`. Each attempt spins up
/// a fresh client/process; we retry a few times so a single flaky attempt doesn't fail the
/// suite. A genuinely-broken transport (the bugs this batch fixes — string-id requests
/// silently dropped, `registerCapability` never ACKed, no crash/time-out handling) fails
/// every attempt and is still reported.
@MainActor
@Suite("LSPClient end-to-end (requires sourcekit-lsp)")
struct LSPClientEndToEndTests {
    /// Transient diagnostics so a flaky run still leaves a trail. No-op unless `LSP_DEBUG=1`.
    private func diag(_ msg: String) {
        guard ProcessInfo.processInfo.environment["LSP_DEBUG"] == "1" else { return }
        let url = URL(fileURLWithPath: "/tmp/e2e_diag.txt")
        let data = (msg + "\n").data(using: .utf8)!
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        } else if let fh = try? FileHandle(forUpdating: url) {
            try? fh.seekToEnd()
            try? fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func makeTempFile() throws -> (file: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lsp-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Main.swift")
        // A local struct with two members: sourcekit resolves `s` without a workspace index,
        // and the completion response is tiny (~1KB) instead of the ~200KB Array-member list
        // that starves sourcekit-lsp under `swift test`. See docs/MEMORY.md #20.
        let source = "struct S { var name: String = \"\"; var id: Int = 0 }\nlet s = S()\ns.\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        return (file, root)
    }

    /// One connect→open→completion pass against a fresh `sourcekit-lsp`. Throws on any
    /// transport/decoding failure; returns the completion items on success.
    private func attemptCompletion() async throws -> [CompletionItem] {
        let (file, root) = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: root) }

        let content = try String(contentsOf: file)
        let client = LSPClient(
            descriptor: .init(
                id: "sourcekit-lsp", displayName: "SourceKit-LSP",
                command: [LanguageServerRegistry.sourceKitLSPPath!],
                languageIdentifiers: ["swift"]
            ),
            rootURL: root
        )
        defer { await client.disconnect() }

        diag("connecting")
        await client.connect()
        diag("ready=\(client.isReady) connected=\(client.isConnected) err=\(String(describing: client.lastError))")
        guard client.isReady else {
            throw NSError(
                domain: "LSPClientEndToEndTests", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "sourcekit-lsp not ready: \(client.lastError ?? "unknown")"]
            )
        }

        // Give the server a moment to finish dynamic registration before exercising it.
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let uri = file.absoluteString
        diag("opening \(uri)")
        await client.openDocument(uri: uri, languageId: "swift", content: content)
        diag("opened")

        // Caret at the end of `s.` -> the struct's stored members (`name`, `id`).
        let pos = Position(line: 2, character: 2)
        diag("requesting completion \(pos)")
        let items = try await client.completion(at: pos, uri: uri)
        diag("got \(items.count) items: \(items.prefix(5).map(\.label))")
        return items
    }

    @Test("sourcekit-lsp starts, opens, and returns member completions")
    func completionRoundTrip() async throws {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/tmp/e2e_diag.txt"))
        diag("starting")
        guard LanguageServerRegistry.sourceKitLSPPath != nil else { return }

        let expected = ["name", "id"]
        var lastError: Error?
        for attempt in 1...3 {
            diag("attempt \(attempt)")
            do {
                let items = try await attemptCompletion()
                let labels = Set(items.map(\.label))
                if labels.isSuperset(of: Set(expected)) {
                    #expect(!items.isEmpty)
                    return
                }
                diag("attempt \(attempt): got \(items.count) items but missing \(expected); retrying")
            } catch {
                lastError = error
                diag("attempt \(attempt) threw: \(error)")
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let detail = String(describing: lastError)
        Issue.record("sourcekit-lsp returned no completions after 3 attempts; last error: \(detail)")
    }
}
