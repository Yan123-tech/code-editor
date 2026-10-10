import Foundation
import Testing

@testable import CodeEditorLSP

@Suite("ServerCapabilities decoding")
struct ServerCapabilitiesTests {
    /// Build JSON `Data` from a plist-like dictionary, so the fixtures stay free of
    /// fragile string quoting.
    private func data(for object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
    }

    /// A capabilities blob shaped like sourcekit-lsp's real answer, including the
    /// `Bool | options-object` and `Int | options-object` unions that previously failed
    /// the whole `initialize` handshake.
    @Test("object-form textDocumentSync and signatureHelpProvider decode instead of failing")
    func objectFormsDecode() throws {
        let blob: [String: Any] = [
            "textDocumentSync": ["openClose": true, "change": 2, "willSave": true],
            "completionProvider": ["triggerCharacters": [".", "("], "resolveProvider": true],
            "hoverProvider": true,
            "signatureHelpProvider": ["triggerCharacters": [",", ":"]],
            "definitionProvider": true,
            "referencesProvider": true,
            "workspaceSymbolProvider": true,
        ]
        let caps = try JSONDecoder().decode(ServerCapabilities.self, from: data(for: blob))

        #expect(caps.supportsCompletion == true)
        #expect(caps.completionProvider?.triggerCharacters == [".", "("])
        #expect(caps.supportsHover)
        #expect(caps.supportsDefinition)
        #expect(caps.textDocumentSync == nil)
        #expect(caps.signatureHelpProvider == nil)
    }

    @Test("minimal and bare-bool blobs decode too")
    func minimalAndBoolForms() throws {
        let minimal = ["completionProvider": ["triggerCharacters": ["."]]]
        let caps = try JSONDecoder().decode(
            ServerCapabilities.self, from: data(for: minimal)
        )
        #expect(caps.supportsCompletion)
        #expect(!caps.supportsHover)

        let bools: [String: Any] = [
            "completionProvider": [:] as [String: Any],
            "hoverProvider": true,
        ]
        let caps2 = try JSONDecoder().decode(ServerCapabilities.self, from: data(for: bools))
        #expect(caps2.supportsCompletion)
        #expect(caps2.supportsHover)
    }
}
