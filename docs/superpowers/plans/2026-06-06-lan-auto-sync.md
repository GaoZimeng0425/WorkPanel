# 局域网自动同步 (LAN auto-sync) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 同一 WiFi 下两台 Mac 的 WorkPanel 通过 Bonjour 自动发现并周期性互相拉取/合并任务数据(最新者胜),无需手动操作、无需公网。

**Architecture:** 仅拉取、双向收敛——每台 Mac 跑一个绑局域网的 HTTP 服务应答 `GET /sync`(返回 `SyncService.exportData(includeSettings:false)`,不含密钥),同时用 `NWBrowser` 发现对端、定时器 + 发现即触发对每个对端 `GET /sync` 并 `SyncService.merge`。复用既有 `HTTPRequest`/`HTTPResponse` 与 `MCPServer` 的 `NWListener`+`MainActor.assumeIsolated` 模式;新建独立监听器(不动 loopback-only 的 MCP 服务)。共享配对码鉴权。

**Tech Stack:** Swift / SwiftUI / SwiftData / Network.framework (`NWListener` / `NWBrowser` / `NWConnection` / Bonjour) / Observation / Swift Testing。

**测试运行约定:** 整包 `xcodebuild test` 可能拖死 testmanagerd;按 suite 运行:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/<SuiteName>
```
活动网络部分(NWListener/NWBrowser/NWConnection 实时 socket、Bonjour)不做单测(与 `MCPServer` 一致),改为编译验证 + 双机手动验证;每个任务把**纯逻辑**抽成可单测的静态函数并 TDD。

**新文件位置:** `WorkPanel/Sync/LAN/` 与 `WorkPanelTests/` 下的文件由 filesystem-synced group 自动纳入,**不要**编辑 `project.pbxproj`。

**已存在、可依赖的设施:**
- `SyncService`(`@MainActor enum`):`exportData(context:now:) throws -> Data`、`parse(_:) throws -> SyncDocument`、`merge(_:into:includeSettings:calendar:) throws -> SyncReport`。`SyncDocument.encoder/.decoder`、`SyncDocument.currentSchemaVersion == 1`。
- `HTTPRequest.parse(_:) -> HTTPRequest?`(`.method`/`.path`/`.headers`(小写键)/`.body`/`.isComplete`),`HTTPResponse.json/.unauthorized/.methodNotAllowed/.build(status:reason:headers:body:)`。
- `MCPServer.authorized(_ headers:[String:String], token:String) -> Bool`(`nonisolated static`,检查 `Authorization: Bearer <token>`)——配对码鉴权直接复用它。
- `MCPServer` 的实时 socket 模式:`l.start(queue: .main)`,连接回调里 `MainActor.assumeIsolated { … }`。
- `AppSettings`(`enum`,`enum Key { static let … }` + 类型化访问器 + `registerDefaults()`)。`AppDelegate` 用 `startOrStopMCP()`/`restartMCP()` + 观察 `.mcpSettingsChanged` 通知启停 `MCPServer`。

---

## Task 1: `SyncService.exportData(includeSettings:)` 开关(密钥泄露修复)

**Files:**
- Modify: `WorkPanel/Sync/SyncService.swift`
- Test: `WorkPanelTests/SyncServiceExportTests.swift`

- [ ] **Step 1: 写失败测试** — 在 `WorkPanelTests/SyncServiceExportTests.swift` 的 struct 内追加:

```swift
    @Test func exportWithoutSettingsOmitsSecrets() throws {
        let ctx = try makeContext()
        ctx.insert(TodoTask(title: "A"))
        try ctx.save()
        let data = try SyncService.exportData(context: ctx, includeSettings: false)
        let doc = try SyncService.parse(data)
        // includeSettings:false → settings 全部字段为 nil(不读取任何偏好,线上无密钥)
        #expect(doc.settings.aiAPIKey == nil)
        #expect(doc.settings.mcpToken == nil)
        #expect(doc.settings.appearance == nil)
        #expect(doc.tasks.count == 1)
    }
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceExportTests
```
Expected: 编译失败(`exportData` 无 `includeSettings` 形参)。

- [ ] **Step 3: 加形参** — 在 `WorkPanel/Sync/SyncService.swift` 把 `exportData` 改为:

```swift
    static func exportData(context: ModelContext,
                           includeSettings: Bool = true,
                           now: Date = .now) throws -> Data {
        let tasks   = try context.fetch(FetchDescriptor<TodoTask>())
        let columns = try context.fetch(FetchDescriptor<BoardColumn>())
        let plans   = try context.fetch(FetchDescriptor<DayPlan>())
        let doc = SyncDocument(
            schemaVersion: SyncDocument.currentSchemaVersion,
            exportedAt: now,
            tasks: tasks.map(SyncTaskDTO.init),
            columns: columns.map(SyncColumnDTO.init),
            dayPlans: plans.map(SyncDayPlanDTO.init),
            settings: includeSettings ? SyncSettings.snapshot() : SyncSettingsDTO()
        )
        return try SyncDocument.encoder.encode(doc)
    }
```
(只改 `settings:` 一行的取值 + 新增形参;默认 `true` 使既有调用方——`SettingsView.runExport`、`SyncServiceExportTests` 的其它用例——行为不变。)

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceExportTests
```
Expected: PASS(4 个用例:原 3 个 + 新增 1 个)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/SyncService.swift WorkPanelTests/SyncServiceExportTests.swift
git commit -m "feat(sync): exportData(includeSettings:) — omit secrets for LAN serving"
```

---

## Task 2: LAN 同步的 `AppSettings` 键与访问器

**Files:**
- Modify: `WorkPanel/Store/AppSettings.swift`

> 说明:这是声明式配置,与现有 `AppSettings` 访问器(如 `mcpToken` 的「无则生成」)同形;`AppSettings` 在本项目无单测,这里同样以**编译验证**为准,不强加会污染 `UserDefaults.standard` 的测试。逻辑性更强的部分在后续任务里抽成纯函数 TDD。

- [ ] **Step 1: 加键** — 在 `AppSettings.Key` 里(`aiPrompts` 之后)追加:

```swift
        static let lanSyncEnabled = "lanSyncEnabled"
        static let lanSyncPort = "lanSyncPort"
        static let lanSyncPairingCode = "lanSyncPairingCode"
        static let lanSyncIntervalSeconds = "lanSyncIntervalSeconds"
        static let syncInstanceID = "syncInstanceID"
        static let lanSyncDeviceName = "lanSyncDeviceName"
```

- [ ] **Step 2: 注册默认值** — 在 `registerDefaults()` 的字典里追加两项(放在 `Key.mcpPort: 8787,` 之后):

```swift
            Key.lanSyncEnabled: false,
            Key.lanSyncPort: 8788,
            Key.lanSyncIntervalSeconds: 30,
```

- [ ] **Step 3: 加类型化访问器** — 在 `AppSettings` 里(`aiConfigured` 之后)追加:

```swift
    static var lanSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.lanSyncEnabled)
    }
    static var lanSyncPort: Int {
        let p = UserDefaults.standard.integer(forKey: Key.lanSyncPort)
        return p == 0 ? 8788 : p
    }
    static var lanSyncIntervalSeconds: Int {
        let s = UserDefaults.standard.integer(forKey: Key.lanSyncIntervalSeconds)
        return s == 0 ? 30 : s
    }
    static var lanSyncPairingCode: String {
        UserDefaults.standard.string(forKey: Key.lanSyncPairingCode) ?? ""
    }
    /// 本机稳定身份,用于 Bonjour 服务名与自身过滤;无则生成一次(与 mcpToken 同模式)。
    static var syncInstanceID: String {
        if let s = UserDefaults.standard.string(forKey: Key.syncInstanceID), !s.isEmpty { return s }
        let s = UUID().uuidString
        UserDefaults.standard.set(s, forKey: Key.syncInstanceID)
        return s
    }
    /// 展示给对端的设备名,默认取本机名。
    static var lanSyncDeviceName: String {
        if let n = UserDefaults.standard.string(forKey: Key.lanSyncDeviceName), !n.isEmpty { return n }
        return Host.current().localizedName ?? "Mac"
    }
```

- [ ] **Step 4: 编译验证**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/AppSettings.swift
git commit -m "feat(sync): AppSettings keys/accessors for LAN sync"
```

---

## Task 3: `SyncClient` — 拉取对端文档(纯解析 TDD + 实时 NWConnection)

**Files:**
- Create: `WorkPanel/Sync/LAN/SyncClient.swift`
- Test: `WorkPanelTests/SyncClientTests.swift`

- [ ] **Step 1: 写失败测试** — create `WorkPanelTests/SyncClientTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncClientTests {
    /// 构造一个最小合法 SyncDocument 的 JSON body。
    private func docBody() throws -> Data {
        let doc = SyncDocument(schemaVersion: 1, exportedAt: Date(timeIntervalSince1970: 0),
                               tasks: [], columns: [], dayPlans: [], settings: SyncSettingsDTO())
        return try SyncDocument.encoder.encode(doc)
    }

    private func response(status: Int, reason: String, body: Data) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    @Test func parsesValid200Response() throws {
        let resp = response(status: 200, reason: "OK", body: try docBody())
        let doc = try SyncClient.parseResponse(resp)
        #expect(doc.schemaVersion == 1)
    }

    @Test func throwsOnNon200() throws {
        let resp = response(status: 401, reason: "Unauthorized", body: Data())
        #expect(throws: SyncClient.ClientError.self) {
            try SyncClient.parseResponse(resp)
        }
    }

    @Test func throwsOnMalformedResponse() {
        #expect(throws: (any Error).self) {
            try SyncClient.parseResponse(Data("garbage no crlf".utf8))
        }
    }

    @Test func throwsOnUnknownSchemaBody() throws {
        let bad = Data(#"{"schemaVersion":999,"exportedAt":"2026-01-01T00:00:00Z","tasks":[],"columns":[],"dayPlans":[],"settings":{}}"#.utf8)
        let resp = response(status: 200, reason: "OK", body: bad)
        #expect(throws: (any Error).self) {   // SyncService.parse 拒绝未知版本
            try SyncClient.parseResponse(resp)
        }
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncClientTests
```
Expected: 编译失败(`SyncClient` 未定义)。

- [ ] **Step 3: 实现** — create `WorkPanel/Sync/LAN/SyncClient.swift`:

```swift
import Foundation
import Network

/// 向对端发 `GET /sync` 并把响应解析为 SyncDocument。
@MainActor
enum SyncClient {
    enum ClientError: Error, Equatable {
        case malformed
        case http(Int)
    }

    /// 纯函数:整段 HTTP 响应字节 → SyncDocument。状态非 200 抛 .http;无法解析抛 .malformed;
    /// body 非法或版本不符由 SyncService.parse 抛出。
    nonisolated static func parseResponse(_ data: Data) throws -> SyncDocument {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let headerString = String(data: data.subdata(in: data.startIndex..<headerEnd.lowerBound),
                                        encoding: .utf8),
              let statusLine = headerString.components(separatedBy: "\r\n").first
        else { throw ClientError.malformed }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else { throw ClientError.malformed }
        guard status == 200 else { throw ClientError.http(status) }
        let body = data.subdata(in: headerEnd.upperBound..<data.endIndex)
        return try SyncService.parse(body)
    }

    /// 实时:连到对端 Bonjour 端点,发 GET /sync(带配对码),累积响应直到完整或连接关闭,解析返回。
    /// 实时 socket 部分不单测;以编译 + 双机手动验证。
    static func fetch(from endpoint: NWEndpoint, code: String,
                      timeout: TimeInterval = 5) async throws -> SyncDocument {
        let conn = NWConnection(to: endpoint, using: .tcp)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SyncDocument, Error>) in
            var finished = false
            func finish(_ result: Result<SyncDocument, Error>) {
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(with: result)
            }

            let request = "GET /sync HTTP/1.1\r\nHost: workpanel\r\nAuthorization: Bearer \(code)\r\nConnection: close\r\n\r\n"

            func receive(_ buffer: Data) {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isDone, error in
                    MainActor.assumeIsolated {
                        var acc = buffer
                        if let data { acc.append(data) }
                        // 头部完整且 body 满足 Content-Length 即可解析;或连接关闭后用已收到的字节解析。
                        if let req = HTTPRequest.parse(acc), req.isComplete {
                            finish(Result { try Self.parseResponse(acc) })
                        } else if isDone {
                            finish(Result { try Self.parseResponse(acc) })
                        } else if let error {
                            finish(.failure(error))
                        } else {
                            receive(acc)
                        }
                    }
                }
            }

            conn.stateUpdateHandler = { state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        conn.send(content: Data(request.utf8),
                                  completion: .contentProcessed { sendErr in
                                      MainActor.assumeIsolated {
                                          if let sendErr { finish(.failure(sendErr)) }
                                          else { receive(Data()) }
                                      }
                                  })
                    case .failed(let e):
                        finish(.failure(e))
                    case .cancelled:
                        finish(.failure(ClientError.malformed))
                    default:
                        break
                    }
                }
            }
            conn.start(queue: .main)
            // 超时兜底
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(ClientError.http(408)))
            }
        }
    }
}
```
注:`HTTPRequest.parse` 解析的是「请求」,但其头/体分割与 `Content-Length` 判断对响应同样适用(我们只用 `isComplete` 判断 body 是否到齐);状态码与最终解析仍走 `parseResponse`。若编译器对 `withCheckedThrowingContinuation` 内捕获 `NWConnection`(非 Sendable)报错,请如实报告,不要私自改写语义。

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncClientTests
```
Expected: PASS(4 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/LAN/SyncClient.swift WorkPanelTests/SyncClientTests.swift
git commit -m "feat(sync): SyncClient GET /sync + response parsing"
```

---

## Task 4: `SyncPeerServer` — 应答 GET /sync 并 Bonjour 广播(纯路由 TDD + 实时监听)

**Files:**
- Create: `WorkPanel/Sync/LAN/SyncPeerServer.swift`
- Test: `WorkPanelTests/SyncPeerServerTests.swift`

- [ ] **Step 1: 写失败测试** — create `WorkPanelTests/SyncPeerServerTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncPeerServerTests {
    private func request(method: String, path: String, code: String?) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let code { headers["authorization"] = "Bearer \(code)" }
        return HTTPRequest(method: method, path: path, headers: headers, body: Data())
    }
    private func status(of response: Data) -> Int {
        let head = String(decoding: response, as: UTF8.self)
        let line = head.components(separatedBy: "\r\n").first ?? ""
        return Int(line.split(separator: " ").dropFirst().first.map(String.init) ?? "") ?? 0
    }

    @Test func validGetSyncReturns200WithBody() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/sync", code: "secret"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 200)
    }
    @Test func wrongCodeReturns401() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/sync", code: "wrong"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 401)
    }
    @Test func missingCodeReturns401() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/sync", code: nil),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 401)
    }
    @Test func nonGetReturns405() {
        let resp = SyncPeerServer.route(request(method: "POST", path: "/sync", code: "secret"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 405)
    }
    @Test func unknownPathReturns404() {
        let resp = SyncPeerServer.route(request(method: "GET", path: "/nope", code: "secret"),
                                        code: "secret", body: { Data("{}".utf8) })
        #expect(status(of: resp) == 404)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncPeerServerTests
```
Expected: 编译失败(`SyncPeerServer` 未定义)。

- [ ] **Step 3: 实现** — create `WorkPanel/Sync/LAN/SyncPeerServer.swift`:

```swift
import Foundation
import Network

/// 绑局域网的 HTTP 服务,Bonjour 广播 `_workpanel._tcp`,应答 `GET /sync`(配对码鉴权)。
/// 独立于只绑 loopback 的 MCPServer——避免把 MCP 工具暴露到网络。
@MainActor
final class SyncPeerServer {
    private let port: UInt16
    private let code: String
    private let instanceID: String
    private let deviceName: String
    private let context: ModelContext
    private var listener: NWListener?

    init(port: UInt16, code: String, instanceID: String, deviceName: String, context: ModelContext) {
        self.port = port
        self.code = code
        self.instanceID = instanceID
        self.deviceName = deviceName
        self.context = context
    }

    /// 纯路由:GET /sync + 正确配对码 → 200 + body();非 GET → 405;配对码错/缺 → 401;其它路径 → 404。
    @MainActor
    static func route(_ req: HTTPRequest, code: String, body: () throws -> Data) -> Data {
        guard req.method == "GET" else { return HTTPResponse.methodNotAllowed() }
        guard MCPServer.authorized(req.headers, token: code) else { return HTTPResponse.unauthorized() }
        guard req.path == "/sync" else { return HTTPResponse.build(status: 404, reason: "Not Found") }
        do { return HTTPResponse.json(try body()) }
        catch { return HTTPResponse.build(status: 500, reason: "Internal Server Error") }
    }

    func start() {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: .tcp, on: nwPort) else { return }
        l.service = NWListener.Service(name: instanceID, type: "_workpanel._tcp",
                                       txtRecord: NWTXTRecord(["device": deviceName]))
        l.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }
        l.start(queue: .main)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isDone, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var acc = buffer
                if let data { acc.append(data) }
                if let req = HTTPRequest.parse(acc), req.isComplete {
                    let resp = Self.route(req, code: self.code) {
                        try SyncService.exportData(context: self.context, includeSettings: false)
                    }
                    conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
                } else if isDone || error != nil {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: acc)
                }
            }
        }
    }
}
```

- [ ] **Step 4: 运行确认通过 + 编译整体**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncPeerServerTests
```
Expected: PASS(5 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/LAN/SyncPeerServer.swift WorkPanelTests/SyncPeerServerTests.swift
git commit -m "feat(sync): SyncPeerServer serves GET /sync over Bonjour LAN"
```

---

## Task 5: `SyncPeerBrowser` + 自身过滤(纯过滤 TDD + 实时浏览)

**Files:**
- Create: `WorkPanel/Sync/LAN/SyncPeerBrowser.swift`
- Test: `WorkPanelTests/SyncPeerBrowserTests.swift`

- [ ] **Step 1: 写失败测试** — create `WorkPanelTests/SyncPeerBrowserTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncPeerBrowserTests {
    @Test func isSelfMatchesOwnInstanceID() {
        #expect(SyncPeerBrowser.isSelf(serviceName: "ABC-123", ownInstanceID: "ABC-123") == true)
    }
    @Test func isSelfRejectsOtherInstanceID() {
        #expect(SyncPeerBrowser.isSelf(serviceName: "PEER-999", ownInstanceID: "ABC-123") == false)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncPeerBrowserTests
```
Expected: 编译失败(`SyncPeerBrowser` 未定义)。

- [ ] **Step 3: 实现** — create `WorkPanel/Sync/LAN/SyncPeerBrowser.swift`:

```swift
import Foundation
import Network

/// 一个发现到的对端:Bonjour 端点 + 实例名 + 设备名(供展示)。
struct DiscoveredPeer: Identifiable, Equatable {
    let id: String          // 实例名(= 对端 syncInstanceID)
    let deviceName: String
    let endpoint: NWEndpoint

    static func == (a: DiscoveredPeer, b: DiscoveredPeer) -> Bool { a.id == b.id }
}

/// 浏览 `_workpanel._tcp`,维护对端列表(过滤自身),变化时回调。
@MainActor
final class SyncPeerBrowser {
    private let ownInstanceID: String
    private let onChange: ([DiscoveredPeer]) -> Void
    private var browser: NWBrowser?
    private(set) var peers: [DiscoveredPeer] = []

    init(ownInstanceID: String, onChange: @escaping ([DiscoveredPeer]) -> Void) {
        self.ownInstanceID = ownInstanceID
        self.onChange = onChange
    }

    /// 纯函数:Bonjour 服务实例名是否就是本机(用于过滤自己)。
    nonisolated static func isSelf(serviceName: String, ownInstanceID: String) -> Bool {
        serviceName == ownInstanceID
    }

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_workpanel._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        peers = []
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [DiscoveredPeer] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            guard !Self.isSelf(serviceName: name, ownInstanceID: ownInstanceID) else { continue }
            var device = name
            if case let .bonjour(txt) = result.metadata, let d = txt["device"] { device = d }
            found.append(DiscoveredPeer(id: name, deviceName: device, endpoint: result.endpoint))
        }
        peers = found
        onChange(found)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncPeerBrowserTests
```
Expected: PASS(2 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/LAN/SyncPeerBrowser.swift WorkPanelTests/SyncPeerBrowserTests.swift
git commit -m "feat(sync): SyncPeerBrowser discovers peers, filters self"
```

---

## Task 6: `SyncCoordinator` + `LANSyncStatus`(编排;编译验证)

**Files:**
- Create: `WorkPanel/Sync/LAN/SyncCoordinator.swift`

> 说明:编排把已测的部件(server/browser/client/merge)接起来,本身无新纯逻辑可单测;以**编译验证**为准,端到端在 Task 8 后双机手动验证。

- [ ] **Step 1: 实现** — create `WorkPanel/Sync/LAN/SyncCoordinator.swift`:

```swift
import Foundation
import SwiftData
import Observation

/// 给设置面板观察的实时状态(SwiftUI Observation 自动刷新)。
@MainActor
@Observable
final class LANSyncStatus {
    static let shared = LANSyncStatus()
    var isRunning = false
    var peerNames: [String] = []
    var lastSync: String = "尚未同步"
    private init() {}
}

/// 局域网自动同步协调器:持有 server + browser + 轮询定时器;到点 / 发现新对端即拉取并合并。
/// 由 AppDelegate 按设置启停,生命周期与 MCPServer 一致。
@MainActor
final class SyncCoordinator {
    private let context: ModelContext
    private let code: String
    private let intervalSeconds: Int
    private let server: SyncPeerServer
    private var browser: SyncPeerBrowser!
    private var timer: Timer?
    private let status = LANSyncStatus.shared

    init(context: ModelContext) {
        self.context = context
        self.code = AppSettings.lanSyncPairingCode
        self.intervalSeconds = AppSettings.lanSyncIntervalSeconds
        self.server = SyncPeerServer(port: UInt16(AppSettings.lanSyncPort),
                                     code: code,
                                     instanceID: AppSettings.syncInstanceID,
                                     deviceName: AppSettings.lanSyncDeviceName,
                                     context: context)
    }

    func start() {
        server.start()
        browser = SyncPeerBrowser(ownInstanceID: AppSettings.syncInstanceID) { [weak self] peers in
            guard let self else { return }
            self.status.peerNames = peers.map(\.deviceName)
            self.syncAll(peers)                 // 发现变化即同步一轮
        }
        browser.start()
        let t = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.syncAll(self.browser?.peers ?? []) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        status.isRunning = true
    }

    func stop() {
        timer?.invalidate(); timer = nil
        browser?.stop(); browser = nil
        server.stop()
        status.isRunning = false
        status.peerNames = []
    }

    private func syncAll(_ peers: [DiscoveredPeer]) {
        guard !code.isEmpty else { status.lastSync = "未设置配对码"; return }
        for peer in peers {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let doc = try await SyncClient.fetch(from: peer.endpoint, code: self.code)
                    let report = try SyncService.merge(doc, into: self.context, includeSettings: false)
                    self.status.lastSync = "已同步 \(peer.deviceName):新增 \(report.totalInserted),更新 \(report.totalUpdated)"
                } catch {
                    self.status.lastSync = "同步 \(peer.deviceName) 失败"
                }
            }
        }
    }
}
```

- [ ] **Step 2: 编译验证**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED。若 `Timer` 闭包的 actor 隔离报错,改用文中的 `MainActor.assumeIsolated` 包裹(已包裹);若仍报错,如实报告。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/Sync/LAN/SyncCoordinator.swift
git commit -m "feat(sync): SyncCoordinator orchestrates discover+poll+merge; LANSyncStatus"
```

---

## Task 7: `AppDelegate` 启停接线 + `.lanSyncSettingsChanged` 通知

**Files:**
- Modify: `WorkPanel/WorkPanelApp.swift`

- [ ] **Step 1: 加通知名** — 在 `WorkPanel/MCP/MCPServer.swift` 的 `extension Notification.Name` 里(`mcpSettingsChanged` 旁)追加:

```swift
    /// Posted by SettingsView when LAN-sync enable/config changes so AppDelegate can restart the coordinator.
    static let lanSyncSettingsChanged = Notification.Name("lanSyncSettingsChanged")
```

- [ ] **Step 2: 接线 AppDelegate** — 在 `WorkPanel/WorkPanelApp.swift` 的 `AppDelegate` 里:

(a) 加属性(在 `private var mcpServer: MCPServer?` 旁):
```swift
    private var syncCoordinator: SyncCoordinator?
```

(b) 在 `applicationDidFinishLaunching` 里,`startOrStopMCP()` 调用之后追加:
```swift
        NotificationCenter.default.addObserver(forName: .lanSyncSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartSync() }
        }
        startOrStopSync()
```

(c) 加两个方法(在 `restartMCP()` 之后):
```swift
    private func startOrStopSync() {
        if AppSettings.lanSyncEnabled {
            let coordinator = SyncCoordinator(context: SharedModel.container.mainContext)
            coordinator.start()
            syncCoordinator = coordinator
        } else {
            syncCoordinator?.stop()
            syncCoordinator = nil
        }
    }

    private func restartSync() {
        syncCoordinator?.stop()
        syncCoordinator = nil
        startOrStopSync()
    }
```

- [ ] **Step 3: 编译验证**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/WorkPanelApp.swift WorkPanel/MCP/MCPServer.swift
git commit -m "feat(sync): AppDelegate starts/stops SyncCoordinator on settings"
```

---

## Task 8: 设置面板「局域网同步」tab

**Files:**
- Modify: `WorkPanel/UI/SettingsView.swift`

> 说明:UI 实时交互(Bonjour/socket)无法 XCUITest 驱动,本任务以**编译验证 + 双机手动验证**为准。

- [ ] **Step 1: 加 tab 枚举项** — 在 `SettingsView` 的 `private enum SettingsTab` 里:
  - `case` 列表改为:`case shortcuts, general, reminder, mcp, ai, lan`
  - `label` 的 switch 追加:`case .lan: "局域网同步"`
  - `icon` 的 switch 追加:`case .lan: "wifi"`

- [ ] **Step 2: 加 @State 绑定** — 在 `SettingsView` 的 `@State`/`@AppStorage` 区追加:
```swift
    @AppStorage(AppSettings.Key.lanSyncEnabled) private var lanSyncEnabled = false
    @AppStorage(AppSettings.Key.lanSyncPairingCode) private var lanSyncPairingCode = ""
    @State private var lanStatus = LANSyncStatus.shared
```

- [ ] **Step 3: 路由 content** — 在 `content(for:)` 的 switch 追加:
```swift
        case .lan:       lanSection
```

- [ ] **Step 4: 加 lanSection** — 在 `SettingsView` 里(`aiSection` 之后)追加:
```swift
    private var lanSection: some View {
        section("局域网同步", systemImage: "wifi") {
            row("启用", systemImage: "antenna.radiowaves.left.and.right") {
                Toggle("", isOn: $lanSyncEnabled)
                    .labelsHidden().toggleStyle(.switch)
                    .onChange(of: lanSyncEnabled) { _, _ in
                        NotificationCenter.default.post(name: .lanSyncSettingsChanged, object: nil)
                    }
            }
            divider
            row("配对码", systemImage: "key") {
                HStack(spacing: 8) {
                    TextField("两台 Mac 填同一个", text: $lanSyncPairingCode)
                        .labelsHidden().frame(width: 180)
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            NotificationCenter.default.post(name: .lanSyncSettingsChanged, object: nil)
                        }
                    Button("生成") {
                        lanSyncPairingCode = String(UUID().uuidString.prefix(8))
                        NotificationCenter.default.post(name: .lanSyncSettingsChanged, object: nil)
                    }
                    .buttonStyle(NoirPillButtonStyle())
                }
            }
            divider
            row("状态", systemImage: "dot.radiowaves.left.and.right") {
                Text(lanStatus.isRunning ? "运行中" : "已停止")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
            divider
            row("已发现设备", systemImage: "laptopcomputer") {
                Text(lanStatus.peerNames.isEmpty ? "无" : lanStatus.peerNames.joined(separator: "、"))
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
            divider
            row("上次同步", systemImage: "clock.arrow.2.circlepath") {
                Text(lanStatus.lastSync)
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
        }
    }
```

- [ ] **Step 5: 编译验证**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 6: 双机手动验证**

1. 在两台同 WiFi 的 Mac 上各跑 WorkPanel,打开设置 →「局域网同步」。
2. 两台都「启用」,填**同一个配对码**(其中一台点「生成」,另一台手填同样的码)。
3. 状态显示「运行中」,「已发现设备」列出对端设备名(几秒内)。
4. 在 A 机新建一个任务 → 30 秒内(或在 B 机重新发现时)B 机看板出现该任务;反向亦然。
5. 改一个任务标题 → 另一台在下一轮同步后更新为新标题(最新者胜)。
6. 把配对码改成不一致 → 状态显示「同步失败」,数据不再互通。

- [ ] **Step 7: 提交**

```bash
git add WorkPanel/UI/SettingsView.swift
git commit -m "feat(settings): 局域网同步 tab — enable, pairing code, live status"
```

---

## 完成标准

- 单测套件 PASS:`SyncServiceExportTests`(含新 includeSettings:false 用例)、`SyncClientTests`、`SyncPeerServerTests`、`SyncPeerBrowserTests`。
- 回归:`SyncServiceMergeTests`、`SyncDocumentTests`、`SyncSettingsTests`、`SaveTrackingTests`、`TimestampedTests`、`BoardStoreTests` 仍 PASS。
- app 编译通过;设置出现「局域网同步」tab。
- 双机手动验证:同 WiFi、同配对码下自动发现并双向同步;配对码不符则拒绝;LAN 文档不含密钥(`includeSettings:false`)。
- 局域网监听独立于 loopback-only 的 MCP 服务。
