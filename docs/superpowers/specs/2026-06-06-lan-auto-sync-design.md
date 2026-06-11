# 局域网自动同步(Bonjour LAN auto-sync)设计

日期:2026-06-06

## 目标

在同一 WiFi 下,两台 Mac 的 WorkPanel 自动互相同步任务/看板列/日计划,无需手动导出导入、无需公网。建立在已有的 `SyncService`(导出 / 解析 / 合并,最新者胜)与 HTTP 服务设施(`HTTPRequest`/`HTTPResponse`,`MCPServer` 的 `NWListener` 模式)之上。

承接已确认的决策:**自动 / 周期性**同步、**Bonjour 自动发现**、**发现即同步 + 每 N 秒轮询**、**共享配对码**鉴权。

## 协议:仅拉取、双向收敛

每台 Mac 同时**提供**自己的数据并**轮询**对端,无 push、无 POST:

- 每个 app 跑一个小 HTTP 服务,应答 `GET /sync` → 返回 `SyncService.exportData(...)` 的 JSON 文档。
- 每个 app 通过 Bonjour 发现对端,在定时器到点 + 发现新对端时,对每个对端发 `GET /sync` → 把返回文档 `SyncService.merge(...)` 进本地库。
- 因为**双方都轮询**,两边都会收敛到最新者胜的结果,无需单独的 push 路径。这是复用现有合并引擎的最简协议。

被否决的方案:
- push-on-change(改动即推送):与所选「周期性」模型不符,且需观察数据变更。
- leader/中心协调者:两台机器场景下过度设计。

## 组件(新增,位于 `WorkPanel/Sync/LAN/`)

- **`SyncPeerServer`** —— 独立的 `NWListener`,监听专用同步端口(默认 **8788**),以 Bonjour 服务 `_workpanel._tcp` 广播。校验配对码(Bearer)后应答 `GET /sync`。复用现有 `HTTPRequest.parse` / `HTTPResponse`。
- **`SyncPeerBrowser`** —— `NWBrowser` 浏览 `_workpanel._tcp`,维护已发现对端列表,并**过滤掉自己**(每个实例有持久化的 `instanceID`,作为 Bonjour 服务实例名携带;名字等于自身 instanceID 的结果跳过)。
- **`SyncClient`** —— 向对端的 Bonjour 端点开 `NWConnection`,发送带配对码的 `GET /sync`,读取响应、解析为 `SyncDocument`。
- **`SyncCoordinator`(`@MainActor`)** —— 持有 server + browser + 轮询定时器;每次到点 / 发现新对端时拉取并合并;维护状态(是否广播、对端列表、上次同步结果/时间)。由 `AppDelegate` 启停,与 `MCPServer` 同样的生命周期接法(设置开关 → 通知 → 重启)。

**为何用独立监听器而非现有 `MCPServer`:** MCP 服务刻意只绑 `loopback`(`requiredInterfaceType = .loopback`);把它放到局域网会把 MCP 工具暴露到网络。同步监听器是独立的、绑局域网的端点,有自己的鉴权。两者互不影响。

### 自身过滤(self-filter)

`NWBrowser` 会发现本机自己广播的服务。每个实例持久化一个 `syncInstanceID`(UUID),作为 Bonjour 服务实例名;浏览结果中实例名等于自身 `syncInstanceID` 的一律跳过。提供一个纯函数 `isSelf(serviceName:ownInstanceID:) -> Bool` 以便单测。

## 安全与「密钥泄露」修复

- 信任 = **共享配对码**,每次 `GET /sync` 以 `Authorization: Bearer <code>` 携带;不匹配 → `401`。两台 Mac 各存一份(新 UserDefaults 键 `lanSyncPairingCode`)。鉴权用纯函数(与 `MCPServer.authorized` 同形)。
- 传输为可信 WiFi 上的明文 HTTP(链路层已被 WPA 加密)。配对码以明文经局域网传输 —— 家用 / 个人 LAN 可接受。记录 TLS-PSK 为将来加固选项,本期不做。
- **关键修复:** `SyncService.exportData` 目前总是内嵌设置快照,而设置里含**明文 API Key / MCP Token**。每 30s 自动经局域网提供该文档会泄露密钥。因此扩展签名为:
  ```swift
  static func exportData(context: ModelContext, includeSettings: Bool = true, now: Date = .now) throws -> Data
  ```
  当 `includeSettings == false` 时,文档的 `settings` 写入空的 `SyncSettingsDTO()`(不读取任何偏好)。
  - 局域网 `SyncPeerServer` 调 `exportData(context:, includeSettings: false)` —— 线上无密钥。
  - 已有的「文件导出」功能保持默认 `true`(行为不变)。
  - 自动合并同样以 `includeSettings: false` 调 `merge`(不覆盖本机设置)。

## 设置与 UI

新增 UserDefaults 键(集中在 `AppSettings.Key`):
- `lanSyncEnabled: Bool`(默认 false)
- `lanSyncPort: Int`(默认 8788)
- `lanSyncPairingCode: String`
- `lanSyncIntervalSeconds: Int`(默认 30)
- `syncInstanceID: String`(持久化 UUID;首次访问时生成)
- `lanSyncDeviceName: String`(默认取主机名 `Host.current().localizedName`;展示给对端)

新增「局域网同步」设置区(沿用 `section`/`row` 磨砂卡片;放在新 tab 或现有 tab 由实现时按一致性决定,倾向新 tab `case lan`):
- 启用开关(切换 → 发 `.lanSyncSettingsChanged` 通知,`AppDelegate` 重启协调器)。
- 配对码字段 + 「生成」按钮(生成随机码,如 `UUID().uuidString` 前若干位,或复用 token 风格)。两台机器需填同一码。
- 状态行:是否正在广播、已发现对端(按设备名列出)、上次同步时间与结果(成功/失败/配对不符)。
- (端口、间隔可作为次要可编辑项;非必需。)

## 数据流

1. 启用 → `SyncCoordinator.start()`:
   - `SyncPeerServer` 起 `NWListener`(端口 `lanSyncPort`,服务名 = `syncInstanceID`,TXT 记录含 `deviceName`),`l.start(queue: .main)`,新连接经 `MainActor.assumeIsolated` 处理(同 `MCPServer` 模式)。
   - `SyncPeerBrowser` 起 `NWBrowser`,结果变化时更新对端列表(过滤自身),发现新对端立即触发一次该对端的同步。
   - 轮询定时器每 `lanSyncIntervalSeconds` 秒触发一轮。
2. 每轮 / 每个新对端 → 对每个对端:`SyncClient.fetch(peer:, pairingCode:)` → `GET /sync` → 解析 `SyncDocument` → `SyncService.merge(doc, into: SharedModel.container.mainContext, includeSettings: false)`。更新状态。
3. `SyncPeerServer` 收 `GET /sync`:Bearer 配对码有效 → `HTTPResponse.json(try SyncService.exportData(context:, includeSettings: false))`;无效 → `401`;非 `GET /sync` → `404`/`405`(沿用 `HTTPResponse` 既有 helper)。
4. 两台机器都执行 2,故双向收敛。

## 错误处理与边界

- 对端不可达 / 超时 → 状态记「上次同步失败」,下一轮重试;不崩溃、不阻塞主线程(`NWConnection` 回调在 main 队列,合并是快速内存操作)。
- 配对码错误 → 状态标记「配对不符」(对端返回 401)。
- 两机在两次轮询间各改了同一任务 → 最新者胜解决;极近同时的同任务改动可能丢一边(个人两机场景接受)。
- 删除不传播(继承自 `merge`,无 tombstone)。
- 解析失败 / 损坏响应 → 该次同步记失败,跳过。
- `merge` 已 `throws`(存储错误上抛),协调器 catch 后记失败状态。

## 测试

可单测的纯单元:
- 配对码鉴权纯函数(有效 / 无效 / 缺失 Bearer)。
- `isSelf(serviceName:ownInstanceID:)` 自身过滤逻辑。
- `SyncClient` 的「HTTP 响应字节 → `SyncDocument`」解析(喂入预制的合法 / 非法响应)。
- `exportData(includeSettings: false)` 不含密钥:断言文档 `settings` 全部字段为 nil(即便本机 UserDefaults 设了 aiAPIKey 等)。

不自动化(手动双机验证,与 `MCPServer` 实时 socket 不做单测一致):Bonjour 广播 / `NWBrowser` 发现 / 端到端两机收敛。可选地用两个内存 `ModelContainer` + 两个 `SyncCoordinator` 跑环回集成测,但易因 Bonjour 时序而 flaky,不作为必需门槛。

## 范围之外(YAGNI)

- TLS-PSK 加密传输(记为加固选项)。
- tombstone / 删除传播。
- 三台及以上多机拓扑的特殊优化(协议本身可用,但只按两机验证)。
- 跨子网 / 公网同步、中继服务。
- 设置的局域网同步(自动同步刻意只同步数据,不碰设置/密钥)。
- on-change 即时推送(本期为周期轮询)。

## 复用与改动清单

- 改:`SyncService.exportData` 增加 `includeSettings: Bool = true` 参数(文件导出行为不变)。
- 复用:`SyncService.parse` / `merge`、`HTTPRequest` / `HTTPResponse`、`MCPServer` 的 `NWListener` + `MainActor.assumeIsolated` 模式。
- 新增:`WorkPanel/Sync/LAN/` 四个文件 + `AppSettings.Key` 若干键 + 设置 UI 区 + `AppDelegate` 启停接线 + `.lanSyncSettingsChanged` 通知名。
- 新文件由 filesystem-synced group 自动纳入,不改 `project.pbxproj`。
