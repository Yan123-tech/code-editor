import Foundation
import Testing

@testable import CodeEditorCore
@testable import CodeEditorLSP

@Suite("Go Development Adaptation")
struct GoDevelopmentTests {
    @Test("LanguageServerRegistry provides gopls descriptor with staticcheck and analyses")
    func goplsDescriptor() {
        guard let descriptor = LanguageServerRegistry.descriptor(for: "go") else {
            // gopls might not be installed in all test environments; if present, verify configuration
            return
        }
        #expect(descriptor.id == "gopls")
        #expect(descriptor.languageIdentifiers.contains("go"))
        #expect(descriptor.command.contains("serve"))
        #expect(descriptor.initializationOptions?.staticcheck == true)
        #expect(descriptor.initializationOptions?.completeUnimported == true)
        #expect(descriptor.initializationOptions?.analyses["shadow"] == true)
    }

    @Test("InitializeParams encodes gopls initialization options properly in JSON")
    func initializeParamsEncoding() throws {
        let opts = GoplsInitializationOptions(
            staticcheck: true,
            completeUnimported: true,
            deepCompletion: true,
            analyses: ["unusedparams": true]
        )
        let params = InitializeParams(
            processId: 1234,
            rootURI: "file:///workspace",
            capabilities: .default,
            workspaceFolders: [WorkspaceFolder(uri: "file:///workspace", name: "workspace")],
            initializationOptions: opts
        )

        let data = try JSONEncoder().encode(params)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"staticcheck\":true"))
        #expect(json.contains("\"completeUnimported\":true"))
        #expect(json.contains("\"unusedparams\":true"))
    }

    @Test("GoFormatter formats valid Go code when gofmt is present")
    func gofmtValidCode() {
        guard GoFormatter.gofmtPath != nil else { return }
        let unformatted = "package main\n\nfunc main()   {\nprintln(  \"hello\"  )\n}\n"
        let formatted = GoFormatter.format(unformatted)
        #expect(formatted != nil)
        #expect(formatted?.contains("println(\"hello\")") == true)
    }

    @Test("GoFormatter returns nil on Go syntax errors without crashing")
    func gofmtSyntaxError() {
        guard GoFormatter.gofmtPath != nil else { return }
        let broken = "package main\nfunc broken( {\n"
        let formatted = GoFormatter.format(broken)
        #expect(formatted == nil)
    }
}
