import Foundation
import Testing

@testable import CodeEditorCore

@Suite("OpenAI Client & Model Discovery")
struct OpenAIClientTests {

    @Test("normalizeBaseURL handles missing schemes, trailing slashes, and defaults")
    func testNormalizeBaseURL() {
        #expect(
            OpenAIClient.normalizeBaseURL("api.openai.com/v1")?.absoluteString == "https://api.openai.com/v1"
        )
        #expect(
            OpenAIClient.normalizeBaseURL("https://api.openai.com/v1/")?.absoluteString
                == "https://api.openai.com/v1"
        )
        #expect(
            OpenAIClient.normalizeBaseURL("http://localhost:11434")?.absoluteString
                == "http://localhost:11434"
        )
        #expect(
            OpenAIClient.normalizeBaseURL("")?.absoluteString == "https://api.openai.com/v1"
        )
    }

    @Test("modelsURL resolves correct path for /v1 and root endpoints")
    func testModelsURL() {
        let openAI = OpenAIClient.modelsURL(from: "https://api.openai.com/v1")
        #expect(openAI?.absoluteString == "https://api.openai.com/v1/models")

        let localhost = OpenAIClient.modelsURL(from: "http://localhost:11434/v1")
        #expect(localhost?.absoluteString == "http://localhost:11434/v1/models")

        let root = OpenAIClient.modelsURL(from: "https://api.openai.com")
        #expect(root?.absoluteString == "https://api.openai.com/v1/models")
    }

    @Test("chatCompletionsURL resolves chat/completions endpoint")
    func testChatCompletionsURL() {
        let url = OpenAIClient.chatCompletionsURL(from: "https://api.openai.com/v1")
        #expect(url?.absoluteString == "https://api.openai.com/v1/chat/completions")

        let lmStudio = OpenAIClient.chatCompletionsURL(from: "http://localhost:1234/v1")
        #expect(lmStudio?.absoluteString == "http://localhost:1234/v1/chat/completions")
    }

    @Test("parseModelsJSON decodes standard OpenAI model schema")
    func testParseStandardModelsJSON() throws {
        let json = """
            {
              "object": "list",
              "data": [
                { "id": "gpt-4o", "object": "model" },
                { "id": "gpt-4o-mini", "object": "model" },
                { "id": "text-embedding-3-small", "object": "model" }
              ]
            }
            """
        let data = try #require(json.data(using: .utf8))
        let models = try OpenAIClient.parseModelsJSON(data)

        #expect(models == ["gpt-4o", "gpt-4o-mini", "text-embedding-3-small"])
    }

    @Test("parseModelsJSON decodes Ollama native model schema")
    func testParseOllamaModelsJSON() throws {
        let json = """
            {
              "models": [
                { "name": "llama3:latest", "model": "llama3:latest" },
                { "name": "codellama:latest", "model": "codellama:latest" }
              ]
            }
            """
        let data = try #require(json.data(using: .utf8))
        let models = try OpenAIClient.parseModelsJSON(data)

        #expect(models == ["codellama:latest", "llama3:latest"])
    }

    @Test("cleanCompletionText removes markdown code blocks and repeated prefixes")
    func testCleanCompletionText() {
        let fenced = """
            ```swift
            func hello() {
                print("world")
            }
            ```
            """
        let cleaned = OpenAIClient.cleanCompletionText(fenced, prefix: "let x = 1\n")
        #expect(cleaned.contains("func hello()"))
        #expect(!cleaned.contains("```"))

        // Prefix overlap cleanup
        let raw = "func greet() -> String { return \"hi\" }"
        let prefix = "    func "
        let deduplicated = OpenAIClient.cleanCompletionText(raw, prefix: prefix)
        #expect(deduplicated == "greet() -> String { return \"hi\" }")
    }

    @Test("parseCompletionResponse decodes chat completions choice content")
    func testParseCompletionResponse() throws {
        let json = """
            {
              "id": "chatcmpl-123",
              "object": "chat.completion",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "guard let self else { return }"
                  },
                  "finish_reason": "stop"
                }
              ]
            }
            """
        let data = try #require(json.data(using: .utf8))
        let text = try OpenAIClient.parseCompletionResponse(data)
        #expect(text == "guard let self else { return }")
    }
}
