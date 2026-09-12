import Foundation
import AVFoundation
import Testing
@testable import Powerwall_TV

private final class AdvisorURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(buffer, count: count)
            }
            data = result
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        var status = 400
        var response = Data()
        if authorization == "Bearer invalid-test-key" {
            status = 401
            response = Data("secret server detail should not be displayed".utf8)
        } else if authorization == "Bearer isolated-test-key", request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json" {
            if request.url?.path == "/v1/chat/completions", body?["model"] as? String == "grok-4.6",
               let messages = body?["messages"] as? [[String: String]],
               messages.first?["role"] == "system", messages.last?["role"] == "user" {
                status = 200
                let content = messages.last?["content"] == "follow-up" ? "The reserve remains protected." : "Estimate: 2.7 kWh, 10% of 27 kWh."
                let finish = messages.last?["content"] == "truncate" ? "length" : "stop"
                response = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content], "finish_reason": finish]]])
            } else if request.url?.path == "/v1/tts", body?["voice_id"] as? String == "eve",
                      body?["language"] as? String == "en", body?["text"] as? String == "Speak this answer" {
                status = 200
                response = Data([1, 2, 3, 4])
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct GrokAdvisorClientTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["POWERWALL_LIVE_ADVISOR"] == "1"))
    func liveGrokAndVoiceServicesRespond() async throws {
        let key = try #require(KeychainWrapper.standard.string(forKey: "xai_apiKey"))
        let service = GrokAdvisorClient(apiKey: key)
        let answer = try await service.answer(messages: [
            ["role": "system", "content": "This is an integration check. Respond with one short sentence."],
            ["role": "user", "content": "Say that the Powerwall export advisor is ready."]
        ])
        #expect(!answer.isEmpty)
        let audio = try await service.speech(text: answer)
        let player = try AVAudioPlayer(data: audio)
        #expect(player.duration > 0)
        #expect(player.prepareToPlay())
    }

    private func client(key: String = "isolated-test-key") -> GrokAdvisorClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AdvisorURLProtocol.self]
        return GrokAdvisorClient(apiKey: key, session: URLSession(configuration: config))
    }

    @Test func sendsConversationToGrokAndDecodesAnswer() async throws {
        let result = try await client().answer(messages: [["role": "system", "content": "Battery context"], ["role": "user", "content": "Estimate"]])
        #expect(result == "Estimate: 2.7 kWh, 10% of 27 kWh.")
    }

    @Test func supportsFollowUpConversation() async throws {
        let result = try await client().answer(messages: [
            ["role": "system", "content": "Battery context"],
            ["role": "user", "content": "Estimate"],
            ["role": "assistant", "content": "2.7 kWh"],
            ["role": "user", "content": "follow-up"]
        ])
        #expect(result == "The reserve remains protected.")
    }

    @Test func requestsGrokVoiceForAnswer() async throws {
        #expect(try await client().speech(text: "Speak this answer") == Data([1, 2, 3, 4]))
    }

    @Test func rejectsTruncatedEstimate() async {
        await #expect(throws: ExportEstimateError.self) {
            try await client().answer(messages: [["role": "system", "content": "context"], ["role": "user", "content": "truncate"]])
        }
    }

    @Test func authorizationFailureDoesNotExposeResponseBody() async {
        do {
            _ = try await client(key: "invalid-test-key").speech(text: "Speak this answer")
            Issue.record("Expected authorization failure")
        } catch {
            #expect(error.localizedDescription.contains("401"))
            #expect(!error.localizedDescription.contains("secret server detail"))
        }
    }
}
