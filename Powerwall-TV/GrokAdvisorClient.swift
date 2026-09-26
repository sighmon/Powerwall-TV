import Foundation

/// Keeps the user's key out of the conversation and makes both xAI endpoints testable.
struct GrokAdvisorClient {
    let apiKey: String
    var session: URLSession = .shared

    struct Model: Decodable, Identifiable {
        let id: String
        let created: Int
        let input_modalities: [String]
        let output_modalities: [String]
    }

    func models() async throws -> [Model] {
        struct Response: Decodable { let models: [Model] }
        let data = try await request("language-models", method: "GET")
        let models = try JSONDecoder().decode(Response.self, from: data).models
            .filter { $0.input_modalities.contains("text") && $0.output_modalities.contains("text") }
            .sorted {
                if $0.created != $1.created { return $0.created > $1.created }
                return $0.id.compare($1.id, options: .numeric) == .orderedDescending
            }
        guard !models.isEmpty else { throw ExportEstimateError.service("No Grok text models are available", 0) }
        return models
    }

    func answer(messages: [[String: String]], modelID: String = "") async throws -> String {
        let selected = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let model: String
        if selected.isEmpty { model = try await models()[0].id }
        else { model = selected }

        let data = try await request("chat/completions", body: [
            "model": model,
            "messages": messages,
            "max_tokens": 1200,
        ])
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard let choice = try JSONDecoder().decode(Response.self, from: data).choices.first,
              choice.finish_reason != "length",
              !choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportEstimateError.service("Empty or incomplete Grok response", 0)
        }
        return choice.message.content
    }

    struct Voice: Decodable, Identifiable {
        let voice_id: String
        let name: String
        var id: String { voice_id }
    }

    func voices() async throws -> [Voice] {
        struct Response: Decodable { let voices: [Voice] }
        let data = try await request("tts/voices", method: "GET")
        let voices = try JSONDecoder().decode(Response.self, from: data).voices
        guard !voices.isEmpty else { throw ExportEstimateError.service("No Grok voices are available", 0) }
        return voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func speech(text: String, voiceID: String = "luna") async throws -> Data {
        try await request("tts", body: ["text": text, "voice_id": voiceID, "language": "en"])
    }

    private func request(_ endpoint: String, method: String = "POST", body: [String: Any]? = nil) async throws -> Data {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportEstimateError.service("xAI: add an API key in Settings", 401)
        }
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/\(endpoint)")!)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ExportEstimateError.service("xAI", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}
