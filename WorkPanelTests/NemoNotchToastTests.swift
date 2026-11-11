import Testing
import Foundation
@testable import WorkPanel

/// NemoNotchToast 客户端测试:纯函数直测;perform 用临时目录 + 注入 hook,零网络。
struct NemoNotchToastTests {

    // MARK: - 基座

    /// 记录 hook 收到的请求;可注入抛错模拟「NemoNotch 未运行 / 连接失败」。
    private actor RequestLog {
        var requests: [URLRequest] = []
        private var failure: Error?

        func fail(with error: Error) { failure = error }

        func record(_ r: URLRequest) throws {
            if let failure { throw failure }
            requests.append(r)
        }
    }

    private struct TestError: LocalizedError {
        var errorDescription: String? { "connection refused" }
    }

    /// 建临时目录并写入凭据文件(文件名 → 内容),返回目录 URL。
    private func makeDir(files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    // MARK: - makePayload

    @Test func minimalPayloadContainsOnlyRequiredFields() {
        let p = NemoNotchToast.makePayload(app: "WorkPanel", title: "标题")
        #expect(p["schema"] as? Int == 1)
        #expect(p["app"] as? String == "WorkPanel")
        #expect(p["title"] as? String == "标题")
        #expect(p["body"] == nil)
        #expect(p["icon"] == nil)
        #expect(p["jumpBundleId"] == nil)
    }

    @Test func payloadClampsFieldLengthsToContract() {
        let p = NemoNotchToast.makePayload(app: String(repeating: "a", count: 100),
                                           title: String(repeating: "t", count: 200),
                                           body: String(repeating: "b", count: 300),
                                           icon: "sf:bell.badge",
                                           jumpBundleId: String(repeating: "c", count: 300))
        #expect((p["app"] as? String)?.count == 48)
        #expect((p["title"] as? String)?.count == 120)
        #expect((p["body"] as? String)?.count == 280)
        #expect((p["jumpBundleId"] as? String)?.count == 255)
        #expect(p["icon"] as? String == "sf:bell.badge")   // icon 透传不截断
    }

    // MARK: - 凭据文件读取

    @Test func readPortParsesFileAndFallsBack() throws {
        let withPort = try makeDir(files: ["hook-port": "50000\n"])
        #expect(NemoNotchToast.readPort(directory: withPort) == 50000)
        let canonical = try makeDir(files: ["hook-port": "45831\n"])
        #expect(NemoNotchToast.readPort(directory: canonical) == 45831)
        let missing = try makeDir(files: [:])
        #expect(NemoNotchToast.readPort(directory: missing) == 45831)
        let garbage = try makeDir(files: ["hook-port": "abc\n"])
        #expect(NemoNotchToast.readPort(directory: garbage) == 45831)
    }

    @Test func readTokenTrimsAndReturnsNilWhenMissing() throws {
        let withToken = try makeDir(files: ["hook-token": "  secret-token\n"])
        #expect(NemoNotchToast.readToken(directory: withToken) == "secret-token")
        let missing = try makeDir(files: [:])
        #expect(NemoNotchToast.readToken(directory: missing) == nil)
    }

    // MARK: - perform

    @Test func performSkipsSilentlyWithoutToken() async throws {
        let dir = try makeDir(files: ["hook-port": "50000\n"])   // 有端口但无令牌
        let log = RequestLog()
        await NemoNotchToast.perform(app: "WorkPanel", title: "标题", directory: dir,
                                     send: { try await log.record($0) })
        let count = await log.requests.count
        #expect(count == 0)
    }

    @Test func performSendsSignedRequestToHookPort() async throws {
        let dir = try makeDir(files: ["hook-port": "50001\n", "hook-token": "tok\n"])
        let log = RequestLog()
        await NemoNotchToast.perform(app: "WorkPanel", title: "标题", body: "正文",
                                     icon: "sf:bell.badge", jumpBundleId: "com.example.app",
                                     directory: dir, send: { try await log.record($0) })
        let requests = await log.requests
        #expect(requests.count == 1)
        let req = try #require(requests.first)
        #expect(req.url?.absoluteString == "http://127.0.0.1:50001/v1/toast")
        #expect(req.httpMethod == "POST")
        #expect(req.timeoutInterval == 3)
        #expect(req.value(forHTTPHeaderField: "X-NemoNotch-Token") == "tok")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let sent = try JSONSerialization.jsonObject(with: #require(req.httpBody)) as? [String: Any]
        let expected = NemoNotchToast.makePayload(app: "WorkPanel", title: "标题", body: "正文",
                                                  icon: "sf:bell.badge", jumpBundleId: "com.example.app")
        #expect(sent?.count == expected.count)
        #expect(sent?["schema"] as? Int == 1)
        for (key, value) in expected {
            #expect((sent?[key] as? String) == (value as? String))
        }
    }

    @Test func performSwallowsHookErrors() async throws {
        let dir = try makeDir(files: ["hook-port": "50002\n", "hook-token": "tok\n"])
        let log = RequestLog()
        await log.fail(with: TestError())
        // 连接层抛错(NemoNotch 未运行等价):不得向上抛、不得挂起
        await NemoNotchToast.perform(app: "WorkPanel", title: "标题", directory: dir,
                                     send: { try await log.record($0) })
    }
}
