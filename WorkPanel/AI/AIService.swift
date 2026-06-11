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
    nonisolated static func build(config: AIConfig, system: String, user: String, stream: Bool = false) throws -> URLRequest {
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
        // 慢模型/长输出留足时间;流式下这是「两段数据之间」的超时,正常推流会不断刷新它。
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "stream": stream,
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

    /// 解析一行 SSE:`data: {json}` → 取 `choices[0].delta.content`。
    /// `data: [DONE]`、注释、空行、无 content 的块都返回 nil(调用方跳过)。
    nonisolated static func parseStreamLine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta
            }
            let choices: [Choice]
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { return nil }
        return chunk.choices.first?.delta.content
    }
}

/// 出站 AI 服务:读取 AppSettings 配置,发起 OpenAI 兼容请求,返回助手文本。
@MainActor
final class AIService {
    /// 流式补全:逐段产出模型输出的增量文本(delta)。出错以 throwing 结束;调用方累加 delta 即可实时展示。
    func stream(systemPrompt: String, userContext: String) -> AsyncThrowingStream<String, Error> {
        let config = AIConfig(baseURL: AppSettings.aiBaseURL,
                              model: AppSettings.aiModel,
                              apiKey: AppSettings.aiAPIKey)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try AIRequest.build(config: config, system: systemPrompt,
                                                      user: userContext, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        LogService.error("无 HTTP 响应", category: "AI")
                        throw AIError.network("无 HTTP 响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line }
                        LogService.error("HTTP \(http.statusCode) @ \(config.model): \(bodyText.prefix(500))", category: "AI")
                        throw AIError.http(http.statusCode, String(bodyText.prefix(200)))
                    }
                    for try await line in bytes.lines {
                        if let delta = AIRequest.parseStreamLine(line), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    LogService.error("流式请求失败: \(error.localizedDescription)", category: "AI")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 把 AIError 转成给用户看的简短中文提示(用于 Notice)。
    nonisolated static func message(for error: Error) -> String {
        switch error {
        case AIError.notConfigured: return "请先在设置里填写 AI 的 baseURL、模型与 API Key"
        case AIError.network(let m): return "网络错误:\(m)"
        case AIError.http(let code, let body):
            return body.isEmpty ? "请求失败(HTTP \(code))" : "请求失败(HTTP \(code)):\(body)"
        case AIError.decode: return "无法解析模型返回"
        default: return "AI 调用失败"
        }
    }
}
