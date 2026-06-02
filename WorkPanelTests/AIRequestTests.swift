import Testing
import Foundation
@testable import WorkPanel

struct AIRequestTests {
    private let config = AIConfig(baseURL: "https://api.openai.com/v1",
                                  model: "gpt-4o-mini",
                                  apiKey: "sk-test")

    @Test func buildSetsURLMethodAndAuthHeader() throws {
        let req = try AIRequest.build(config: config, system: "S", user: "U")
        #expect(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func buildBodyHasModelAndMessages() throws {
        let req = try AIRequest.build(config: config, system: "S", user: "U")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "gpt-4o-mini")
        let messages = body?["messages"] as? [[String: String]]
        #expect(messages?.count == 2)
        #expect(messages?[0]["role"] == "system")
        #expect(messages?[0]["content"] == "S")
        #expect(messages?[1]["role"] == "user")
        #expect(messages?[1]["content"] == "U")
    }

    @Test func buildTrimsTrailingSlashOnBaseURL() throws {
        let c = AIConfig(baseURL: "https://x.test/v1/", model: "m", apiKey: "k")
        let req = try AIRequest.build(config: c, system: "S", user: "U")
        #expect(req.url?.absoluteString == "https://x.test/v1/chat/completions")
    }

    @Test func buildThrowsNotConfiguredWhenFieldBlank() {
        let c = AIConfig(baseURL: "https://x.test/v1", model: "", apiKey: "k")
        #expect(throws: AIError.notConfigured) {
            _ = try AIRequest.build(config: c, system: "S", user: "U")
        }
    }

    @Test func parseExtractsAssistantContent() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"hello world"}}]}
        """.data(using: .utf8)!
        #expect(try AIRequest.parse(data: json) == "hello world")
    }

    @Test func parseThrowsDecodeOnBadJSON() {
        let json = "{\"oops\":true}".data(using: .utf8)!
        #expect(throws: AIError.decode) {
            _ = try AIRequest.parse(data: json)
        }
    }
}
