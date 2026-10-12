import Foundation

/// Lightweight client for OpenAI-compatible APIs (OpenAI, OpenRouter, Ollama, LM Studio, etc.).
/// Handles model discovery and code completions.
public final class OpenAIClient: Sendable {
    public static let shared = OpenAIClient()

    private let urlSession: URLSession

    public init(session: URLSession = .shared) {
        self.urlSession = session
    }

    // MARK: - URL Helpers

    /// Cleans and normalizes an API base URL (e.g. `https://api.openai.com/v1`).
    public static func normalizeBaseURL(_ urlString: String) -> URL? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = "https://api.openai.com/v1"
        }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return URL(string: trimmed)
    }

    /// Constructs the models URL from a base URL.
    public static func modelsURL(from baseURLString: String) -> URL? {
        guard let base = normalizeBaseURL(baseURLString) else { return nil }
        if base.path.hasSuffix("/v1") {
            return base.appendingPathComponent("models")
        } else if base.path.isEmpty || base.path == "/" {
            return base.appendingPathComponent("v1/models")
        } else {
            return base.appendingPathComponent("models")
        }
    }

    /// Constructs the chat completions URL from a base URL.
    public static func chatCompletionsURL(from baseURLString: String) -> URL? {
        guard let base = normalizeBaseURL(baseURLString) else { return nil }
        if base.path.hasSuffix("/v1") {
            return base.appendingPathComponent("chat/completions")
        } else if base.path.isEmpty || base.path == "/" {
            return base.appendingPathComponent("v1/chat/completions")
        } else {
            return base.appendingPathComponent("chat/completions")
        }
    }

    // MARK: - Models Discovery

    /// Fetches the list of available model identifiers from an OpenAI-compatible endpoint.
    public func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        guard let url = Self.modelsURL(from: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(
                "Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(
                domain: "OpenAIClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models: \(errorText)"]
            )
        }

        return try Self.parseModelsJSON(data)
    }

    /// Parses models JSON payload supporting both standard OpenAI schema and Ollama native schema.
    public static func parseModelsJSON(_ data: Data) throws -> [String] {
        // 1. Try standard OpenAI format: { "data": [ { "id": "..." } ] }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let dataArray = obj["data"] as? [[String: Any]] {
                var models: [String] = []
                for item in dataArray {
                    if let id = item["id"] as? String, !id.isEmpty {
                        models.append(id)
                    }
                }
                if !models.isEmpty {
                    return models.sorted()
                }
            }

            // 2. Try Ollama native format: { "models": [ { "name": "..." } ] }
            if let modelsArray = obj["models"] as? [[String: Any]] {
                var models: [String] = []
                for item in modelsArray {
                    if let name = item["name"] as? String, !name.isEmpty {
                        models.append(name)
                    } else if let model = item["model"] as? String, !model.isEmpty {
                        models.append(model)
                    }
                }
                if !models.isEmpty {
                    return models.sorted()
                }
            }
        }

        return []
    }

    // MARK: - Code Completion

    /// Requests an autocompletion from the OpenAI-compatible API.
    public func complete(
        prefix: String,
        suffix: String,
        language: String,
        baseURL: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard let url = Self.chatCompletionsURL(from: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(
                "Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let prompt = Self.buildPrompt(prefix: prefix, suffix: suffix, language: language)

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content":
                        "You are a fast, accurate code completion engine like GitHub Copilot. Continue the code directly from the cursor position. Output ONLY the raw completion code to insert. Do NOT use markdown code blocks, do NOT write explanations, and do NOT repeat the code already before the cursor.",
                ],
                [
                    "role": "user",
                    "content": prompt,
                ],
            ],
            "temperature": 0.1,
            "max_tokens": 128,
            "stop": ["\n\n\n", "```"],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(
                domain: "OpenAIClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "AI completion error: \(errorText)"]
            )
        }

        let rawCompletion = try Self.parseCompletionResponse(data)
        return Self.cleanCompletionText(rawCompletion, prefix: prefix)
    }

    public static func buildPrompt(prefix: String, suffix: String, language: String) -> String {
        var result = "File language: \(language)\n\n"
        result += "Existing code before cursor:\n\(prefix)\n"
        if !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result += "\nExisting code after cursor:\n\(suffix)\n"
        }
        result += "\nPredict and provide ONLY the immediate next code to insert at cursor:"
        return result
    }

    public static func parseCompletionResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
            if let message = first["message"] as? [String: Any],
                let content = message["content"] as? String
            {
                return content
            }
            if let text = first["text"] as? String {
                return text
            }
        }

        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw NSError(
                domain: "OpenAIClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return ""
    }

    /// Cleans any markdown artifacts or duplicate prefix overlaps from the completion string.
    public static func cleanCompletionText(_ raw: String, prefix: String) -> String {
        var text = raw

        // Strip markdown fences ```lang ... ``` if present
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            } else {
                text = text.replacingOccurrences(of: "```", with: "")
            }
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }

        // Check exact prefix suffix match first
        for len in stride(from: min(50, prefix.count), through: 2, by: -1) {
            let tail = String(prefix.suffix(len))
            if text.hasPrefix(tail) {
                text = String(text.dropFirst(len))
                return text
            }
        }

        // Check trimmed prefix suffix match
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrefix.isEmpty {
            for len in stride(from: min(40, trimmedPrefix.count), through: 2, by: -1) {
                let tail = String(trimmedPrefix.suffix(len))
                if text.hasPrefix(tail) {
                    text = String(text.dropFirst(len))
                    if prefix.hasSuffix(" ") || prefix.hasSuffix("\t") {
                        while text.hasPrefix(" ") || text.hasPrefix("\t") {
                            text.removeFirst()
                        }
                    }
                    break
                }
            }
        }

        return text
    }
}
