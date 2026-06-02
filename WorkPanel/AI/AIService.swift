import Foundation

/// 出站 AI 调用所需的配置三元组(OpenAI 兼容)。
struct AIConfig: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
}

enum AIError: Error, Equatable {
    case notConfigured            // baseURL/model/apiKey 任一为空
    case network(String)          // URLSession 抛出
    case http(Int, String)        // 非 2xx,带状态码与响应体摘要
    case decode                   // 响应 JSON 无法解析出 content
}

/// 请求构造与响应解析:纯函数,无网络,便于单测。
enum AIRequest {
    nonisolated static func build(config: AIConfig, system: String, user: String) throws -> URLRequest {
        let trimmedBase = config.baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedBase.isEmpty,
              !config.model.trimmingCharacters(in: .whitespaces).isEmpty,
              !config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIError.notConfigured
        }
        let base = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        guard let url = URL(string: base + "/chat/completions") else {
            throw AIError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    nonisolated static func parse(data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw AIError.decode
        }
        return content
    }
}

/// 出站 AI 服务:读取 AppSettings 配置,发起 OpenAI 兼容请求,返回助手文本。
@MainActor
final class AIService {
    func run(systemPrompt: String, userContext: String) async throws -> String {
        let config = AIConfig(baseURL: AppSettings.aiBaseURL,
                              model: AppSettings.aiModel,
                              apiKey: AppSettings.aiAPIKey)
        let request = try AIRequest.build(config: config, system: systemPrompt, user: userContext)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIError.network("无 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, String(bodyText.prefix(200)))
        }
        return try AIRequest.parse(data: data)
    }

    /// 把 AIError 转成给用户看的简短中文提示(用于 Notice)。
    nonisolated static func message(for error: Error) -> String {
        switch error {
        case AIError.notConfigured: return "请先在设置里填写 AI 的 baseURL、模型与 API Key"
        case AIError.network(let m): return "网络错误:\(m)"
        case AIError.http(let code, _): return "请求失败(HTTP \(code))"
        case AIError.decode: return "无法解析模型返回"
        default: return "AI 调用失败"
        }
    }
}
