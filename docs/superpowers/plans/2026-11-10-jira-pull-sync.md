# Jira 拉取同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一键从 Jira Cloud 拉取 JQL 匹配的 issue 落地为正式 `TodoTask`,重复拉取幂等合并(本地优先、完成单向收敛),不回写 Jira。

**Architecture:** `JiraClient`(HTTP + 解析,protocol 抽象便于注入)→ `JiraPullService`(合并引擎:按 `jiraKey` 去重、`jiraSyncedAt` 判本地修改、二段查询闭单)→ Settings Jira 区块(手动触发)。denylist 防复活挂在 `TodoStore.delete`。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / Swift Testing / URLSession;Jira Cloud REST v3(`POST /rest/api/3/search/jql`,Basic 鉴权,`nextPageToken` 分页)。

**Spec:** [docs/superpowers/specs/2026-11-10-jira-pull-sync-design.md](../specs/2026-11-10-jira-pull-sync-design.md)

**前置依赖:** [2026-11-10-remove-lan-sync-and-tombstones.md](2026-11-10-remove-lan-sync-and-tombstones.md) 已执行完毕(Tombstone/LAN 已不存在)。

## Global Constraints

- 单向拉取:任何代码路径不得向 Jira 发写请求(只用 POST search/jql 查询)
- Jira Cloud only:域名默认 `antalpha.atlassian.net`;Basic 鉴权 `email:api_token`(Base64);REST v3
- 凭据存 UserDefaults 明文(模式同 `aiAPIKey`);`jiraDismissedKeys` 不进 `SyncSettingsDTO`
- `schemaVersion` 维持 1;`SyncTaskDTO` 新字段为 Optional,缺失解码为 nil
- 拉取/新建路径用普通 `context.save()`,**不用** `saveTracking()`(时间戳由本服务显式控制)
- 分页上限 5 页 × 50 条;二段闭单查询单次 ≤50 key
- 工程为同步文件夹组:新文件直接 `WorkPanel/Sync/Jira/` 落盘即入 target
- 测试命令统一 `rtk test`;Conventional commits(develop 分支)

## Review Focus

1. **完成不复活**:本地已勾完成的 Jira 任务,拉取绝不能改回未完成 → Task 4 `completedLocalTaskStaysCompleted`
2. **本地编辑保护**:拉取后用户改过标题的任务,下轮拉取不得被远端覆盖 → Task 4 `locallyModifiedTaskWinsOnPull`
3. **滑出 JQL 的闭单**:issue 在 Jira 关闭后不再匹配默认 JQL,本地仍须标完成 → Task 4 `absentClosedIssueGetsCompletedViaSecondQuery`
4. **防复活**:本地删除过的 issue 不被重新插入 → Task 4 `dismissedKeyIsNotReinserted` + Task 5 `deleteRecordsJiraKeyInDenylist`
5. **失败不半写**:凭据缺失/HTTP 401 时不动本地库,返回错误信息 → Task 4 `authFailureLeavesStoreUntouchedAndReports`

---

### Task 1: TodoTask 与 SyncTaskDTO 增加 Jira 关联字段

**Files:**
- Modify: `WorkPanel/Models/TodoTask.swift`
- Modify: `WorkPanel/Sync/SyncDocument.swift`(`SyncTaskDTO`)
- Test: `WorkPanelTests/SyncDocumentTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `TodoTask.jiraKey: String?`(默认 nil)、`TodoTask.jiraSyncedAt: Date?`(默认 nil);`SyncTaskDTO` 同名字段参与编解码与 `init(_ t:)`/`apply(to:)` 搬运——后续所有任务依赖这两个属性名

- [ ] **Step 1: 写失败测试**

`SyncDocumentTests` 新增 `taskDTORoundTripsJiraFields`:构造 `TodoTask(title:"x")`,`jiraKey = "PROJ-1"`、`jiraSyncedAt = Date(timeIntervalSince1970: 100)`;`SyncTaskDTO` → encoder → decoder → `apply(to:)` 到新模型,断言两字段还原。

- [ ] **Step 2: 跑测试确认失败**

Run: `rtk test`
Expected: FAIL——`TodoTask` 无 `jiraKey` 成员(编译错)

- [ ] **Step 3: 实现字段**

`TodoTask` 存储属性区加:

```swift
var jiraKey: String? = nil
var jiraSyncedAt: Date? = nil
```

`SyncTaskDTO` 加同名 `var jiraKey: String?`、`var jiraSyncedAt: Date?`(`Codable` 可选缺键自动 nil),`init(_ t:)` 与 `apply(to:)` 各补一行搬运。

- [ ] **Step 4: 跑测试确认通过**

Run: `rtk test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(jira): add jiraKey/jiraSyncedAt to TodoTask and sync DTO"
```

---

### Task 2: AppSettings Jira 键与导出白名单

**Files:**
- Modify: `WorkPanel/Store/AppSettings.swift`
- Modify: `WorkPanel/Sync/SyncSettings.swift`
- Test: `WorkPanelTests/SyncDocumentTests.swift`(沿用既有 SyncSettings 测试所在文件;若无现成 snapshot/apply 用例则新增于该文件)

**Interfaces:**
- Consumes: `AppSettings.Key` 既有模式
- Produces(Task 4/5 依赖的精确访问器):
  - `AppSettings.Key.jiraDomain = "jiraDomain"`、`.jiraEmail = "jiraEmail"`、`.jiraAPIToken = "jiraAPIToken"`、`.jiraJQL = "jiraJQL"`、`.jiraDismissedKeys = "jiraDismissedKeys"`
  - `AppSettings.jiraDomain: String`(空回退 `"antalpha.atlassian.net"`)
  - `AppSettings.jiraEmail: String`、`AppSettings.jiraAPIToken: String`
  - `AppSettings.jiraJQL: String`(空回退默认 JQL,常量 `defaultJQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"`)
  - `AppSettings.jiraConfigured: Bool`(domain+email+token 三者非空)
  - `AppSettings.jiraDismissedKeys: [String]`、`static func jiraDismiss(_ key: String)`(去重追加)、`static func jiraResetDismissed()`
  - `registerDefaults` 登记 `jiraDomain` 默认值与 `jiraJQL` 默认值
  - `SyncSettingsDTO` 增 `jiraDomain/jiraEmail/jiraAPIToken/jiraJQL: String?`,`snapshot`/`apply` 各补 4 行

- [ ] **Step 1: 写失败测试**

`SyncDocumentTests` 新增 `syncSettingsRoundTripsJiraKeys`:用 `UserDefaults(suiteName:)` 临时套件写入 4 个 Jira 键 → `SyncSettings.snapshot(suiteName:)` 断言 DTO 携带 4 值 → encoder/decoder roundtrip → `apply(to: 另一套件)` 断言 4 键写入;同时断言 DTO 编码 JSON **不含** `"jiraDismissedKeys"`。

- [ ] **Step 2: 跑测试确认失败**

Run: `rtk test`
Expected: FAIL(编译错:DTO 无这些成员)

- [ ] **Step 3: 实现**

按 Interfaces 列表实现(照 `aiBaseURL`/`aiAPIKey` 的既有写法照抄结构)。

- [ ] **Step 4: 跑测试确认通过**

Run: `rtk test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(jira): add Jira settings keys and export whitelist entries"
```

---

### Task 3: JiraClient(模型、解析、分页、ADF 提取)

**Files:**
- Create: `WorkPanel/Sync/Jira/JiraClient.swift`
- Test: `WorkPanelTests/JiraClientTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `AppSettings.jiraDomain/jiraEmail/jiraAPIToken`(仅 UI 组装时用;client 自身收构造参数)
- Produces(Task 4 依赖):

```swift
struct JiraIssue: Equatable, Sendable {
    var key: String              // "PROJ-123"
    var summary: String
    var statusCategoryKey: String // "Done" / "Indeterminate" / "New"
    var priorityName: String?     // priority 缺失时 nil
    var duedateDay: String?       // "2026-11-20" 原样;缺省 nil
    var descriptionText: String?  // ADF 提取的纯文本;无 description 时 nil
}

protocol JiraFetching: Sendable {
    /// 内部按 nextPageToken 分页,上限 5 页 × 50 条
    func search(jql: String) async throws -> [JiraIssue]
}

struct JiraClient: JiraFetching {
    init(domain: String, email: String, apiToken: String)
}
```

- HTTP:`POST https://{domain}/rest/api/3/search/jql`,body `{"jql":…,"fields":["summary","status","priority","duedate","description"],"maxResults":50}`,首页后每页带 `nextPageToken`;Basic 头 `Authorization: Basic base64(email:token)`;非 2xx 抛错(401 给「邮箱/API Token 无效」信息)。网络层薄,不写测试。

- [ ] **Step 1: 写失败测试(fixture 驱动,只测解析静态函数)**

`JiraClient` 暴露 `static func parseIssues(_ data: Data) throws -> (issues: [JiraIssue], nextPageToken: String?)` 供测试。测试用内联 JSON fixture:
- `parseExtractsCoreFields`:1 个 issue(summary/statusCategory "Done"/priority "High"/duedate/description ADF)→ 断言 6 字段
- `parseHandlesMissingOptionals`:priority、duedate、description 全缺 → nil/nil/nil,statusCategory 仍有
- `parseExtractsNestedADFText`:description 为嵌套两层 paragraph 的 ADF → 文本以 `\n\n` 连接
- `parseReturnsNextPageToken`:响应含 `nextPageToken` → 返回之
- `paginationCapStopsAtFivePages`:构造 fake `JiraFetching`(实现协议的测试替身,记录调用次数,每次返回 50 条 + token)→ `search(jql:)` 返回 ≤250 条且恰好调用 5 次

- [ ] **Step 2: 跑测试确认失败**

Run: `rtk test`
Expected: FAIL(类型不存在,编译错)

- [ ] **Step 3: 实现 JiraClient**

解码 struct:`{ issues: [{ key, fields: { summary, status: { statusCategory: { key } }, priority: { name }?, duedate: String?, description: ADFNode? } }], nextPageToken: String? }`。
ADF 提取算法(测试未定的部分,照此实现):

```swift
struct ADFNode: Codable { var type: String?; var text: String?; var content: [ADFNode]? }

static func adfPlainText(_ node: ADFNode) -> String {
    // 叶子(type=="text")取 text;块级(paragraph 等)之间以 "\n\n" 连接,行内 content 直接拼接
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `rtk test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(jira): add Jira Cloud client with ADF text extraction and pagination"
```

---

### Task 4: JiraPullService 合并引擎

**Files:**
- Create: `WorkPanel/Sync/Jira/JiraPullService.swift`
- Test: `WorkPanelTests/JiraPullServiceTests.swift`

**Interfaces:**
- Consumes: `JiraFetching`/`JiraIssue`(Task 3)、`TodoTask.jiraKey/jiraSyncedAt`(Task 1)、`TagStore(context:).reconcileFromTasks()`(既有)
- Produces(Task 5 依赖):

```swift
struct JiraPullReport: Equatable {
    var inserted = 0
    var updated = 0        // 远端字段更新
    var completed = 0      // 既有任务被标完成(新建即完成计 inserted)
    var skipped = 0        // 本地优先跳过
    var failedMessage: String?
}

@MainActor
struct JiraPullService {
    init(fetcher: any JiraFetching)
    func pull(context: ModelContext, dismissedKeys: [String], now: Date = .now) async -> JiraPullReport
}
```

合并算法(设计定稿,照此实现):
1. `fetcher.search(jql:)` 抛错 → `failedMessage = 错误描述`,直接返回,**不动库**;`dismissed` = `Set(dismissedKeys)`
2. 本地按 `jiraKey` 建索引:`fetch(FetchDescriptor<TodoTask>())` 过滤 `jiraKey != nil`;同 key 多条取 `createdAt` 最早一条为目标,其余不参与
3. 逐条远端 issue:
   - 无本地且 key ∈ dismissed → 跳过
   - 无本地 → 插入:`title = "[\(key)] \(summary)"`、`notes = descriptionText ?? ""`、`tags = ["jira"]`、`columnID = nil`、`deadline` = `duedateDay` 按本地时区折当日 23:59(用 `Calendar.current`,`duedateDay` nil 则 nil)、priority 映射(`Highest`/`Critical`/`High`→`.high`;`Medium`→`.medium`;`Low`/`Lowest`→`.low`;其它/nil→`.medium`)、`isCompleted = (statusCategoryKey == "Done")`(完成则 `completedAt = now`)、`jiraKey = key`、`modifiedAt = jiraSyncedAt = now`;`inserted += 1`
   - 有本地且本地 `isCompleted` → `skipped += 1`(完成永不回退)
   - 有本地、远端 Done → `isCompleted = true; completedAt = now; modifiedAt = now`(**不动 `jiraSyncedAt`**);`completed += 1`
   - 有本地、远端未 Done 且 `modifiedAt > jiraSyncedAt`(本地改过)→ `skipped += 1`
   - 否则(本地未改)→ 覆盖 title/notes/deadline/priority/tags(规则同插入),`modifiedAt = jiraSyncedAt = now`;`updated += 1`
4. 二段闭单:`absent` = 本地 jiraKey 非 nil、未完成、且不在本次结果的 key(**不排除 dismissed**——dismissed 只是插入抑制,更新与闭单照常,避免数据陈旧),按 key 排序取前 50;非空则 `fetcher.search(jql: "issuekey IN (k1,k2,…)")`;返回中 `statusCategoryKey == "Done"` 的 → 本地对应任务标完成(`modifiedAt = now`,不动 `jiraSyncedAt`,`completed += 1`);该查询抛错则忽略(不影响主结果)
5. `TagStore(context: context).reconcileFromTasks()`;普通 `try context.save()`(不用 `saveTracking()`);返回 report

- [ ] **Step 1: 写失败测试(in-memory container + fake fetcher;全部只验证合并,不发网络)**

测试基座:`ModelContainer(for: TodoTask.self, BoardColumn.self, Tag.self, DayPlan.self, configurations: 内存)`,`JiraFetching` 替身按脚本返回预设 `[JiraIssue]`。用例与断言:
- `newIssueInsertsTaskWithKeyPrefixAndJiraTag`:插入断言 title 前缀、tags、jiraKey、columnID nil
- `secondPullUpdatesUnchangedLocalTask`:首轮后改 summary 再拉 → title 更新、`updated == 1`
- `locallyModifiedTaskWinsOnPull`:首轮后本地改 title(saveTracking 或手抬 modifiedAt)→ 再拉 title 不变、`skipped == 1`
- `completedLocalTaskStaysCompleted`:本地勾完成后再拉(远端仍开放)→ `isCompleted` 仍 true、`skipped == 1`
- `remoteDoneCompletesLocalTask`:远端 statusCategory Done → 本地完成、`jiraSyncedAt` 不变
- `remoteDoneOnLocallyModifiedTaskCompletesWithoutLosingProtection`:本地改过 + 远端 Done → 完成、`jiraSyncedAt` 保持旧值(下轮仍本地优先)
- `absentClosedIssueGetsCompletedViaSecondQuery`:首轮插入开放 issue;第二轮 fake 首查返回空、二段查询(`issuekey IN` 那次调用)返回 Done → 本地完成
- `dismissedKeyIsNotReinserted`:dismissed key + 远端返回该 issue → 不插入、`inserted == 0`
- `duplicateLocalTasksPickEarliest`:手动插两条同 jiraKey(不同 createdAt)→ 再拉只更新较早一条
- `authFailureLeavesStoreUntouchedAndReports`:fake 首查抛错 → `failedMessage` 非空、本地无任何插入且原有数据不变
- `deadlineMapsToEndOfDay`:duedateDay "2026-11-20" → deadline 本地时区 23:59(用固定 `TimeZone` 的 Calendar 断言日界)

- [ ] **Step 2: 跑测试确认失败**

Run: `rtk test`
Expected: FAIL(类型不存在,编译错)

- [ ] **Step 3: 实现 JiraPullService**

按上面合并算法实现;时间统一用注入的 `now` 参数,保证测试确定性。

- [ ] **Step 4: 跑测试确认通过**

Run: `rtk test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(jira): add pull merge engine with local-wins and one-way completion"
```

---

### Task 5: 删除挂钩 denylist 与设置面板 Jira 区块

**Files:**
- Modify: `WorkPanel/Store/TodoStore.swift`(`delete` 增一行 denylist 记录)
- Modify: `WorkPanel/UI/Settings/SettingsView.swift`(tab 枚举 + `jiraSection`)
- Test: `WorkPanelTests/TodoStoreTests.swift`

**Interfaces:**
- Consumes: Task 2 `AppSettings.jiraDismiss/jiraDismissedKeys/jiraResetDismissed/jiraConfigured/jiraJQL`;Task 4 `JiraPullService.pull(context:dismissedKeys:now:)`;Task 3 `JiraClient.init(domain:email:apiToken:)`
- Produces: `TodoStore.delete(_ task:)` 签名不变(计划 1 终审已移除 `now:` 参数),行为增「`task.jiraKey` 非 nil 时 `AppSettings.jiraDismiss(key)`」;设置面板出现「Jira 同步」tab

- [ ] **Step 1: 写失败测试**

`TodoStoreTests` 新增 `deleteRecordsJiraKeyInDenylist`:测试前 `UserDefaults.standard.removeObject(forKey: AppSettings.Key.jiraDismissedKeys)`(用 `defer` 收尾再清一次防污染);插入带 `jiraKey = "PROJ-9"` 的任务 → `store.delete(task)` → 断言 `AppSettings.jiraDismissedKeys == ["PROJ-9"]`;删除无 jiraKey 任务 → 列表不变。

- [ ] **Step 2: 跑测试确认失败**

Run: `rtk test`
Expected: FAIL(列表为空)

- [ ] **Step 3: 实现 TodoStore 挂钩**

`delete` 内、`context.delete(task)` 前取 `task.jiraKey`,非 nil 则 `AppSettings.jiraDismiss(key)`。

- [ ] **Step 4: 跑测试确认通过**

Run: `rtk test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(jira): record deleted issue keys to denylist"
```

- [ ] **Step 6: 设置面板 Jira 区块**

`SettingsTab` 枚举加 `jira` case(label「Jira 同步」,排在 `ai` 后),`content(for:)` 加分支。`jiraSection` 复用既有 `section`/`row` 帮助方法,行结构:
- 域名 `TextField`(占位 `antalpha.atlassian.net`,绑定 `@AppStorage(AppSettings.Key.jiraDomain)`)
- 邮箱 `TextField`、API Token `SecureField`(同模式绑定)
- JQL:`DisclosureGroup("高级:自定义 JQL")` 内 `TextField`(绑 `@AppStorage(Key.jiraJQL)`,占位显示默认 JQL)
- 「立即拉取」按钮:`AppSettings.jiraConfigured` 为 false 时 disabled;点击 `Task { let r = await JiraPullService(fetcher: JiraClient(domain: AppSettings.jiraDomain, email: AppSettings.jiraEmail, apiToken: AppSettings.jiraAPIToken)).pull(context: SharedModel.container.mainContext, dismissedKeys: AppSettings.jiraDismissedKeys); Notice.show(摘要文本) }`;摘要格式:`r.failedMessage != nil ? "拉取失败:\(msg)" : "新增 \(r.inserted) · 更新 \(r.updated) · 完成 \(r.completed) · 跳过 \(r.skipped)"`;拉取期间按钮显示进度态(`.task`/`isPulling` @State 置位防重入)
- 「已忽略 n 项 · 恢复」:`AppSettings.jiraDismissedKeys` 非空时显示,点击 `AppSettings.jiraResetDismissed()`

- [ ] **Step 7: 编译验证**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(jira): add settings panel Jira pull section"
```

---

### Task 6: 收尾验证

**Files:** 无新改动(验证任务)

- [ ] **Step 1: 全量测试 + 构建**

Run: `rtk test` 与 `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -3`
Expected: 全绿 + BUILD SUCCEEDED

- [ ] **Step 2: 人工冒烟清单(留给用户,需真实 API Token)**

设置面板填邮箱 + Token(atlassian.com → 账户安全 → 创建 API Token)→ 立即拉取 → 看板/任务列表出现 `[KEY] 标题` 任务;Jira 里关闭一个 issue 再拉 → 本地完成;本地删除一个拉取任务再拉 → 不复活。
