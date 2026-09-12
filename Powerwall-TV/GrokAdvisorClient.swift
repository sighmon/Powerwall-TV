import Foundation

/// Keeps the user's key out of the conversation and makes both xAI endpoints testable.
struct GrokAdvisorClient {
    let apiKey: String
    var session: URLSession = .shared

    func answer(messages: [[String: String]]) async throws -> String {
        let data = try await request("chat/completions", body: [
            "model": "grok-4.6",
            "messages": messages,
            "max_tokens": 1200,
            "reasoning_effort": "low",
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

    func speech(text: String) async throws -> Data {
        try await request("tts", body: ["text": text, "voice_id": "luna", "language": "en"])
    }

    private func request(_ endpoint: String, body: [String: Any]) async throws -> Data {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportEstimateError.service("xAI: add an API key in Settings", 401)
        }
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/\(endpoint)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ExportEstimateError.service("xAI", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}
