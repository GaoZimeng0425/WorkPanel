import Foundation

/// NemoNotch 外部 Toast API(公开契约 v1)客户端:POST http://127.0.0.1:<port>/v1/toast,
/// 端口/令牌运行时读 `~/.NemoNotch/` 下文件(端口可能漂移,每次发送现读)。
/// fire-and-forget:一切失败仅 debug 日志、静默跳过,绝不影响调用方主流程;
/// 不带 `key`,每次推送独立一次性提醒卡。
nonisolated enum NemoNotchToast {
    /// 单次发送:入参为完整请求。生产走 URLSession,测试注入替身(对齐 JiraClient.PageSender)。
    typealias Hook = @Sendable (URLRequest) async throws -> Void

    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".NemoNotch", isDirectory: true)

    /// 同步入口:后台发送,不抛、不阻塞、结果不回传。
    static func show(app: String, title: String, body: String = "", icon: String = "",
                     jumpBundleId: String = "") {
        Task.detached {
            await perform(app: app, title: title, body: body, icon: icon, jumpBundleId: jumpBundleId)
        }
    }

    /// 发送流程:无令牌静默跳过 → 组载荷 → 发请求。测试经 directory/send 注入,零网络。
    static func perform(app: String, title: String, body: String = "", icon: String = "",
                        jumpBundleId: String = "", directory: URL = defaultDirectory,
                        send: Hook? = nil) async {
        guard let token = readToken(directory: directory) else {
            LogService.debug("toast skip: no hook-token", category: "NemoNotch")
            return
        }
        let payload = makePayload(app: app, title: title, body: body, icon: icon, jumpBundleId: jumpBundleId)
        guard let url = URL(string: "http://127.0.0.1:\(readPort(directory: directory))/v1/toast"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-NemoNotch-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do { try await (send ?? urlSessionSend)(req) }
        catch { LogService.debug("toast send failed: \(error.localizedDescription)", category: "NemoNotch") }
    }

    /// 生产发送:连接失败向上抛由 perform 吞;非 2xx(含 400/401)只记日志,不重试。
    private static let urlSessionSend: Hook = { req in
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            LogService.debug("toast rejected: HTTP \(code)", category: "NemoNotch")
        }
    }

    /// 载荷即完整卡面:空可选字段省略;长度按契约上限截断;不带 key(一次性卡)。
    static func makePayload(app: String, title: String, body: String = "", icon: String = "",
                            jumpBundleId: String = "") -> [String: Any] {
        var p: [String: Any] = ["schema": 1, "app": String(app.prefix(48)), "title": String(title.prefix(120))]
        if !body.isEmpty { p["body"] = String(body.prefix(280)) }
        if !icon.isEmpty { p["icon"] = icon }
        if !jumpBundleId.isEmpty { p["jumpBundleId"] = String(jumpBundleId.prefix(255)) }
        return p
    }

    /// hook-port:一行数字;缺失/非法回落 45831。
    static func readPort(directory: URL) -> Int {
        let text = (try? String(contentsOf: directory.appendingPathComponent("hook-port"), encoding: .utf8)) ?? ""
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 45831
    }

    /// hook-token:整文件为令牌(去首尾空白);读不到/为空返回 nil(调用方静默跳过)。
    static func readToken(directory: URL) -> String? {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("hook-token"), encoding: .utf8)
        else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
