# NemoNotch Toast(Jira 新任务提示)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jira 拉取出现新任务时,通过本机 NemoNotch 外部 Toast API 在刘海下方弹一张卡片;每次拉取最多一张,带数量与任务标题。

**Architecture:** 新增独立 fire-and-forget 客户端 `NemoNotchToast`(读 `~/.NemoNotch` 凭据 → POST `/v1/toast`,一切失败静默);`JiraPullReport` 增加新任务标题清单;`JiraPullRunner.pullNow`(手动/自动拉取唯一入口,自带 `isRunning` 防重入)在拉取成功且有插入时发一次 toast——不带 `key` 即一次性卡,天然满足"一次更新一窗"。

**Tech Stack:** Swift 6 / Foundation URLSession / Swift Testing(工程为文件系统同步组,新文件入目录即入 target;测试沿用 in-memory ModelContainer + FakeFetcher 模式)

**Spec:** 无独立 spec 文档;契约 = 用户提供的《NemoNotch 外部 Toast API · Agent 接入指南 v1》,要点内嵌下方 Global Constraints。方案已经 plan mode 批准(数量+标题、手动/自动都弹)。

## Global Constraints

- 端点固定 `POST http://127.0.0.1:<port>/v1/toast`;port 读 `~/.NemoNotch/hook-port`(一行数字),缺失/非法回落 `45831`;每次发送前现读。
- 令牌读 `~/.NemoNotch/hook-token` 整文件 → 请求头 `X-NemoNotch-Token`;读不到 → 本次静默跳过(不发请求)。
- 载荷:`schema: 1` 固定;`app` 1–48 字符;`title` 1–120;`body` ≤280;`icon` 仅 `sf:<SF Symbol 名>`;`jumpBundleId` ≤255;空串可选字段直接省略;**不带 `key`**(一次性提醒卡)。
- 任何失败(无令牌/连接拒绝/超时/非 200)不得影响主流程:fire-and-forget、3 秒超时、吞错误(仅 `LogService.debug(category: "NemoNotch")`),不重试。
- toast 固定文案参数:`app "WorkPanel"`、`icon "sf:bell.badge"`、`jumpBundleId "com.nemo.BrightnessApp.WorkPanel"`(点卡片激活本应用)。
- 测试零网络:客户端网络层可注入(`Hook` 闭包,对齐 `JiraClient.PageSender` 模式);目录参数注入默认 `~/.NemoNotch`。
- commit 走 conventional commits(develop 分支,不 push)。

## Review Focus

契约隐含、最可能咬人的输入类;每行已把测试钉到所属任务:

1. token 文件缺失/不可读 → 不发请求、不崩(Task 1:`perform` 无 token 时 hook 零调用)
2. NemoNotch 未运行或端口漂移 → 端口回落 45831、连接层抛错被吞不上抛(Task 1:`readPort` 回落 + `perform` 捕获 hook 抛错)
3. 超长 title/body/app/jumpBundleId → 按契约上限截断(Task 1:`makePayload` 截断测试)
4. 一次拉取新增多条 → 仍只一张卡,标题带总数、正文取前 3 条标题 + "等 N 项"(Task 3:`toastContent` 测试;结构上 `pullNow` 只调一次 `show`)
5. 拉取失败/写入失败(`failedMessage != nil`)或零新增 → 不弹(Task 3:`toastContent` 返回 nil)
6. 新建即 Done 的 issue → 也算新任务,计入标题清单(Task 2:更新 `newDoneIssueInsertsAsCompleted`)

---

### Task 1: NemoNotchToast 客户端

**Files:**
- Create: `WorkPanel/Notifications/NemoNotchToast.swift`
- Test: `WorkPanelTests/NemoNotchToastTests.swift`

**Interfaces:**
- Produces: `nonisolated enum NemoNotchToast`
  - `typealias Hook = @Sendable (URLRequest) async throws -> Void`
  - `static let defaultDirectory: URL`(`~/.NemoNotch`)
  - `static func show(app: String, title: String, body: String = "", icon: String = "", jumpBundleId: String = "")` — 同步入口,内部 `Task.detached` 调 `perform`,任何情况不抛不阻塞
  - `static func perform(app: String, title: String, body: String = "", icon: String = "", jumpBundleId: String = "", directory: URL = defaultDirectory, send: Hook? = nil) async` — internal,测试直调;`send` 缺省走 URLSession 实现(3 秒超时,非 2xx 仅 debug 日志)
  - `static func makePayload(app: String, title: String, body: String = "", icon: String = "", jumpBundleId: String = "") -> [String: Any]`
  - `static func readPort(directory: URL) -> Int` / `static func readToken(directory: URL) -> String?`

- [ ] **Step 1: 写失败测试 `NemoNotchToastTests.swift`**(Swift Testing,临时目录注入,actor 记录 hook 收到的 URLRequest)
  - `makePayload` 最小载荷 = `["schema": 1, "app": …, "title": …]`;body/icon/jumpBundleId 空串 → 键不存在
  - `makePayload` 超长截断:title>120、body>280、app>48、jumpBundleId>255 各截到上限
  - `readPort("45831\n")` → 45831;目录无文件 → 45831;内容非数字 → 45831
  - `readToken` 有文件 → 去首尾空白;无文件 → nil
  - `perform` 无 token 文件 → hook 零调用
  - `perform` 有 token+port 文件 → hook 恰一次;断言 URL `http://127.0.0.1:<port>/v1/toast`、头 `X-NemoNotch-Token`/`Content-Type: application/json`、httpBody JSON 解码等于 `makePayload` 输出
  - `perform` hook 抛错 → 不向上抛(测试自身不 fail 即通过)
- [ ] **Step 2: 跑测确认失败**

  Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/NemoNotchToastTests CODE_SIGNING_ALLOWED=NO`
  Expected: FAIL,`cannot find 'NemoNotchToast' in scope`
- [ ] **Step 3: 实现 `NemoNotchToast.swift`**

  结构对齐 `WorkPanel/Sync/Jira/JiraClient.swift`(nonisolated + 注入 sender + 静态纯函数);`makePayload` 用 `String.prefix` 截断(grapheme 安全);`perform` 顺序:readToken(nil→debug log+return)→ makePayload → makeRequest(readPort,3 秒超时)→ `try await (send ?? urlSessionSend)(req)`,`catch` 仅 debug log。
- [ ] **Step 4: 跑测确认通过**

  Run: 同 Step 2。Expected: PASS(全绿)
- [ ] **Step 5: Commit**

  ```bash
  git add WorkPanel/Notifications/NemoNotchToast.swift WorkPanelTests/NemoNotchToastTests.swift
  git commit -m "feat(notifications): NemoNotch toast client, fire-and-forget"
  ```

### Task 2: JiraPullReport 携带新任务标题

**Files:**
- Modify: `WorkPanel/Sync/Jira/JiraPullService.swift`(report 结构体 + 插入分支)
- Test: `WorkPanelTests/JiraPullServiceTests.swift`

**Interfaces:**
- Produces: `JiraPullReport.insertedTitles: [String] = []`(默认值,既有 memberwise 构造与 `==` 断言兼容);插入分支 `apply` 之后 append `t.title`(格式 `"[KEY] summary"`;新建即 Done 同样计入)

- [ ] **Step 1: 先改断言(红)**:99、118 行两处 `JiraPullReport(inserted: 1)` 补 `insertedTitles: ["[PROJ-1] 修复登录"]` / `["[A-1] 远端标题"]`(与各用例 issue 工厂 summary 对应);并在一个多 issue 用例(如 `unmappedOrMissingColumnFallsBackToNil`,2 条插入)断言顺序 `["[OC-1] …", "[OC-2] …"]`
- [ ] **Step 2: 跑测确认失败**

  Run: `xcodebuild test … -only-testing:WorkPanelTests/JiraPullServiceTests`
  Expected: FAIL(inserted 断言不等)
- [ ] **Step 3: 实现**:report 加字段;插入分支 `report.insertedTitles.append(t.title)`
- [ ] **Step 4: 跑测确认通过**
- [ ] **Step 5: Commit**

  ```bash
  git add WorkPanel/Sync/Jira/JiraPullService.swift WorkPanelTests/JiraPullServiceTests.swift
  git commit -m "feat(jira): pull report carries inserted task titles"
  ```

### Task 3: pullNow 触发 toast + 文案

**Files:**
- Modify: `WorkPanel/Sync/Jira/JiraPullService.swift`(`JiraPullRunner`)
- Test: `WorkPanelTests/JiraPullServiceTests.swift`(追加 `toastContent` 用例;纯函数,零网络)

**Interfaces:**
- Consumes: Task 1 `NemoNotchToast.show(app:title:body:icon:jumpBundleId:)`;Task 2 `insertedTitles`
- Produces: `static func toastContent(_ r: JiraPullReport) -> (title: String, body: String)?` — `failedMessage != nil || inserted == 0` → nil;否则 title `"Jira 新增 \(n) 个任务"`,body = 前 3 条标题 `"；"` 连接,`n > 3` 追加 `"；等 \(n) 项"`

- [ ] **Step 1: 写失败测试**:nil 条件(失败消息、零新增);3 条 → 标题 "Jira 新增 3 个任务"、正文三条无后缀;5 条 → 前 3 条 + "；等 5 项";1 条 → 无后缀
- [ ] **Step 2: 跑测确认失败**(cannot find `toastContent`)
- [ ] **Step 3: 实现**:`toastContent` 纯函数 + `pullNow` 在 Notice 逻辑后追加

  ```swift
  if let c = toastContent(report) {
      NemoNotchToast.show(app: "WorkPanel", title: c.title, body: c.body,
                          icon: "sf:bell.badge", jumpBundleId: "com.nemo.BrightnessApp.WorkPanel")
  }
  ```
- [ ] **Step 4: 跑测确认通过**
- [ ] **Step 5: Commit**

  ```bash
  git add WorkPanel/Sync/Jira/JiraPullService.swift WorkPanelTests/JiraPullServiceTests.swift
  git commit -m "feat(jira): one NemoNotch toast per pull when new tasks arrive"
  ```

### Task 4: 全量回归 + 活体验收

**Files:** 无新改动(除非验收暴露问题,修正 fixup 到对应任务)

- [ ] **Step 1: 全量测试(每计划收尾一次,含 UI 测试——会反复拉起 app,属预期)**

  Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  Expected: 全部 suite 通过(含既有 JiraClient/TodoStore/SyncDocument 等;`WorkPanelUITestsLaunchTests.testLaunch` 为既有 flake,单跑复核即可)
- [ ] **Step 2: 对真实 NemoNotch 的 curl 验收**(契约 §5 适用项)
  - 无 token 头 → 期望 `401`
  - 最小合法载荷(仅 schema/app/title)→ 期望 `200 {"status":"ok"}`,刘海下出现卡片(用户目视确认)
  - `{"schema":1}` 缺 title → 期望 `400`,reason 提及 title
- [ ] **Step 3: 端到端(用户配合)**:app 运行中删掉一条本地已关联任务 → 手动拉取 → 恰好一张卡、点卡片切回 WorkPanel;无新增的常规拉取不弹
