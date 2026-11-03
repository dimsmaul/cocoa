import Foundation

public struct AIServiceError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class AIService: @unchecked Sendable {
    public static let shared = AIService()

    private init() {}

    // MARK: - Test Connection
    public func testConnection() async throws -> String {
        let settings = AppSettings.shared
        guard settings.isAIConfigured else {
            throw AIServiceError("API Key is missing. Please enter your API key in Settings.")
        }

        let provider = settings.aiProvider
        let model = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIServiceError("Model name is empty.")
        }

        let prompt = "Say 'Cocoa AI Connected successfully!' in fewer than 6 words."

        switch provider {
        case .anthropic:
            return try await callAnthropic(apiKey: settings.aiAPIKey, model: model, prompt: prompt)
        case .openai:
            return try await callOpenAICompatible(
                baseURL: "https://api.openai.com/v1",
                apiKey: settings.aiAPIKey,
                model: model,
                prompt: prompt
            )
        case .gemini:
            return try await callGemini(apiKey: settings.aiAPIKey, model: model, prompt: prompt)
        case .ollama:
            let baseURL = settings.aiCustomBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await callOpenAICompatible(
                baseURL: baseURL.isEmpty ? "http://localhost:11434/v1" : baseURL,
                apiKey: "ollama",
                model: model,
                prompt: prompt
            )
        case .custom:
            let baseURL = settings.aiCustomBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await callOpenAICompatible(
                baseURL: baseURL,
                apiKey: settings.aiAPIKey,
                model: model,
                prompt: prompt
            )
        }
    }

    // MARK: - Smart Subtask Breakdown
    public func breakdownTask(title: String, notes: String = "") async throws -> [String] {
        let settings = AppSettings.shared
        guard settings.isAIConfigured else {
            throw AIServiceError("AI is not configured. Please add an API Key in Settings.")
        }

        let systemPrompt = settings.aiSystemPrompt
        let userContent = """
        Task Title: "\(title)"
        Task Notes: "\(notes)"

        Break down this task into 3 to 6 small, actionable, sequential subtasks.
        Return ONLY a JSON array of strings, without any extra text or markdown formatting.
        Example format:
        ["First subtask step", "Second subtask step", "Third subtask step"]
        """

        let rawResponse: String
        switch settings.aiProvider {
        case .anthropic:
            rawResponse = try await callAnthropic(
                apiKey: settings.aiAPIKey,
                model: settings.aiModel,
                prompt: userContent,
                system: systemPrompt
            )
        case .openai:
            rawResponse = try await callOpenAICompatible(
                baseURL: "https://api.openai.com/v1",
                apiKey: settings.aiAPIKey,
                model: settings.aiModel,
                prompt: userContent,
                system: systemPrompt
            )
        case .gemini:
            rawResponse = try await callGemini(
                apiKey: settings.aiAPIKey,
                model: settings.aiModel,
                prompt: userContent,
                system: systemPrompt
            )
        case .ollama:
            let baseURL = settings.aiCustomBaseURL.isEmpty ? "http://localhost:11434/v1" : settings.aiCustomBaseURL
            rawResponse = try await callOpenAICompatible(
                baseURL: baseURL,
                apiKey: "ollama",
                model: settings.aiModel,
                prompt: userContent,
                system: systemPrompt
            )
        case .custom:
            rawResponse = try await callOpenAICompatible(
                baseURL: settings.aiCustomBaseURL,
                apiKey: settings.aiAPIKey,
                model: settings.aiModel,
                prompt: userContent,
                system: systemPrompt
            )
        }

        return parseSubtasks(from: rawResponse)
    }

    // MARK: - Provider Calls

    private func callAnthropic(apiKey: String, model: String, prompt: String, system: String? = nil) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIServiceError("Invalid Anthropic URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var bodyDict: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        if let system, !system.isEmpty {
            bodyDict["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError("Invalid network response")
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError("Anthropic Error (\(httpResponse.statusCode)): \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIServiceError("Failed to parse Anthropic message response")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callOpenAICompatible(baseURL: String, apiKey: String, model: String, prompt: String, system: String? = nil) async throws -> String {
        let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = cleanBase.hasSuffix("/chat/completions") ? cleanBase : "\(cleanBase)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw AIServiceError("Invalid endpoint URL: \(endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && key != "ollama" {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        var messages: [[String: String]] = []
        if let system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": prompt])

        let bodyDict: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 1024
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError("Invalid network response")
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError("AI Provider Error (\(httpResponse.statusCode)): \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIServiceError("Failed to parse chat response choices")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callGemini(apiKey: String, model: String, prompt: String, system: String? = nil) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(cleanModel):generateContent?key=\(cleanKey)"
        guard let url = URL(string: endpoint) else {
            throw AIServiceError("Invalid Gemini endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var fullPrompt = prompt
        if let system, !system.isEmpty {
            fullPrompt = "\(system)\n\n\(prompt)"
        }

        let bodyDict: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError("Invalid network response")
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError("Gemini Error (\(httpResponse.statusCode)): \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIServiceError("Failed to parse Gemini response parts")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Output Parsing Helpers
    private func parseSubtasks(from raw: String) -> [String] {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown ```json or ``` code fences
        if clean.hasPrefix("```") {
            let lines = clean.components(separatedBy: "\n")
            let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            clean = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try direct JSON array decoding
        if let data = clean.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        // Fallback: parse bullet points or numbered lists
        let lines = clean.components(separatedBy: "\n")
        var results: [String] = []

        for line in lines {
            var item = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isEmpty { continue }

            // Strip leading - or * or numbered list like "1. "
            if item.hasPrefix("- ") || item.hasPrefix("* ") || item.hasPrefix("• ") {
                item = String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if let dotIndex = item.firstIndex(of: ".") {
                let prefix = item[..<dotIndex]
                if Int(prefix) != nil {
                    item = String(item[item.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                }
            }

            // Strip quotes
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: "\"[]"))
            if !item.isEmpty {
                results.append(item)
            }
        }

        return results.isEmpty ? [raw] : results
    }
}
