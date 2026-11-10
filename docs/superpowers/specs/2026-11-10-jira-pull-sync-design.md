# Jira 拉取同步设计

日期:2026-11-10

## 意图与动机

用户的正式工作任务在 Jira Cloud(antalpha.atlassian.net)上,日常规划在 WorkPanel。目前要在两个系统间手动切换。希望把分配给自己的 Jira issue 拉取到 WorkPanel,变成正式任务,与个人任务统一进入看板、当日规划与完成勾选。

**已确认:单向拉取(Jira → WorkPanel),不回写 Jira。**

## 目标 / 非目标 / 反目标

**目标**
- 一键拉取 JQL 匹配的 issue,落地为正式 `TodoTask`
- 重复拉取幂等:按 issue key 去重,远端变更(标题/优先级/截止日/关闭)更新本地
- 拉取任务与普通任务行为一致:可编辑、可规划、可勾完成、可删除

**非目标**
- 不回写 Jira(本地完成、改字段都不影响 Jira)
- 不做定时自动拉取(仅手动按钮;定时是后续可加项)
- 不做双向冲突协议

**反目标**
- 做成只读镜像列表(issue 无法参与当日规划,等于浏览器标签页)
- 本地已完成的任务被远程复活
- 本地删除的任务下次拉取被复活

## 约束

- Jira Cloud,Basic 鉴权(邮箱 + API Token),REST API v3
- 鉴权凭据存 UserDefaults 明文——与现有 `aiAPIKey`、`mcpToken` 的既定模式一致
- 现有导入/导出(newest-wins 全量合并)语义不能被破坏;拉取产生的 `modifiedAt` 变更要能被导出文件正确携带
- 前置依赖:LAN 自动同步与 Tombstone 已按 [2026-11-10-remove-lan-sync-and-tombstones-design.md](2026-11-10-remove-lan-sync-and-tombstones-design.md) 移除,本设计假定其不存在

## 方案(已选定 A,次级取舍见各节)

- **A. 落地为正式 TodoTask(选定)**:按 issue key 关联,任务可编辑可规划。代价是模型加字段 + 合并规则。用户已确认。
- B. 只读镜像区:实现最简,但 Jira 任务进不了当日规划,体现不了统一管理价值。已否决。

## 鉴权与设置

`AppSettings` 新增键(明文,模式同 `aiAPIKey`):

- `jiraDomain`(默认 `antalpha.atlassian.net`)
- `jiraEmail`
- `jiraAPIToken`
- `jiraJQL`(默认 `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`)
- `jiraConfigured` 计算属性:三项凭据齐全

`SyncSettingsDTO`(导入/导出白名单)增加 `jiraDomain`/`jiraEmail`/`jiraAPIToken`/`jiraJQL`,与 `aiAPIKey` 同待遇——仅在导入时勾选「同时导入设置」才写入;`jiraDismissedKeys` 是每机状态,不进白名单(同 `lastPlannedDay` 的排除模式)。`schemaVersion` 保持 1(可选字段不升级,沿 tombstone spec 先例)。

设置面板新增「Jira 拉取」区块:域名、邮箱、API Token(SecureField)、JQL(可折叠的高级项)、「立即拉取」按钮、结果反馈(如「新增 3 · 更新 2 · 完成 1 · 失败 0」)、「恢复已忽略的 Jira 任务」(清空 denylist)。

## API

`POST https://{domain}/rest/api/3/search/jql`

```json
{ "jql": "...", "fields": ["summary", "status", "priority", "duedate", "labels"], "maxResults": 50 }
```

- Basic 鉴权 `email:api_token`(URLSession,`dataTask`);凭据缺失或 401 → 明确报错反馈
- 分页用响应里的 `nextPageToken` 带回请求体,上限 5 页(250 条),超出则只拉前 250 条并在反馈中提示截断
- description 用 ADF(Atlassian Document Format)JSON:递归收集 `content[].content[].text` 文本节点,以空行拼接为纯文本(不做富文本/markdown 转换)

## 模型变更

`TodoTask` 新增两个可选字段(轻量迁移,旧行为 nil):

```swift
var jiraKey: String?        // 如 "PROJ-123";拉取去重与关联的稳定键
var jiraSyncedAt: Date?     // 上次成功应用远端数据的时刻;本地修改判定基准
```

`SyncTaskDTO`(导入/导出编解码)同步增加这两个字段,否则备份/换机迁移会丢失 Jira 关联,导入后任务退化为普通任务。

不建独立 JiraIssue 映射表——两个字段够用,少一张表少一份状态。

## 合并规则(核心)

按 `jiraKey` 匹配本地任务(FetchDescriptor 谓词;若同 key 多条——双机各自拉取的场景——取 `createdAt` 最早的一条更新,其余不动)。

**本地优先判定**:本地 `modifiedAt > jiraSyncedAt` 视为「拉取后被本地改过」,**跳过远端字段更新**(title/notes/deadline/priority/tags 全部保留本地);否则远端覆盖。

**完成状态单向收敛**(不受本地优先判定限制——跳过的只有 title/notes/deadline/priority/tags):
- 远端 `statusCategory == Done` → 本地 `isCompleted = true`
- 本地已完成的,**任何情况下不被拉取改回未完成**(用户已确认「不复活」;即使 Jira 里 reopened)
- **仅应用完成时**(本地改过、字段更新被跳过的场景):只抬 `modifiedAt = .now`(导出/导入按 newest-wins 携带完成状态),**不更新 `jiraSyncedAt`**(保住本地修改保护,下轮拉取仍不会冲掉本地编辑)

**应用远端变更时**:字段写入后,`modifiedAt = jiraSyncedAt = .now`,用普通 `context.save()`(**不是** `saveTracking()`,与导入合并路径同理——打点由本服务显式控制,且新 `modifiedAt` 保证后续导出/导入按 newest-wins 携带最新状态)。新建任务同样走普通 `save()` 并显式设这两个时间戳。

**闭单传播(二段查询)**:默认 JQL 排除了 Done,issue 关闭后会从结果中消失而非带着 Done 状态出现。处理:拉取结束后,取本地「已关联 jiraKey 且未完成、但不在本次结果中」的 key 集合,发起第二次查询(`issuekey IN (k1,k2,...)`,同样走 search/jql,单次 ≤50 key,超出下轮再查),按返回的当前状态处理:已关闭 → 本地标记完成;其它(如被取消分配)→ 本地不动。

**防复活 denylist**:本地删除带 `jiraKey` 的任务时,把 key 记入 UserDefaults `jiraDismissedKeys`(String 数组);拉取插入时跳过命中的 key(更新与二段闭单查询照常,避免数据陈旧)。设置面板提供清空入口。

挂钩点唯一:所有本地删除路径(TaskListView/TaskEditorView/MCP 等)都收敛到 `TodoStore.delete`,在这一处记录即可。Tombstone 机制已随 LAN 同步移除,不存在其它删除入口。

## 字段映射

| Jira 字段 | TodoTask | 规则 |
|---|---|---|
| key | `jiraKey` | 稳定关联键 |
| summary | `title` | 存 `"[KEY] summary"`(前缀入标题,任何视图零改动即可识别);远端 summary 变更时重写 |
| description (ADF) | `notes` | 递归提取纯文本 |
| priority.name | `priorityRaw` | Highest/High→high,Critical/Highest 均按 high;Medium→medium;Low/Lowest→low;站内自定义名不匹配→medium |
| duedate | `deadline` | Jira 日期无时分,存当日 23:59 本地时区 |
| status.statusCategory | `isCompleted` | Done→true(单向,见合并规则) |
| labels | 不映射 | tags 固定为 `["jira"]`(供过滤;本地后加的标签因本地优先判定不会被冲掉) |
| — | `columnID` | 新建时 nil(默认任务列表/收件箱位置) |
| — | `recurrence` / `urgencyOverride` / `snoozedUntil` / `planOrder` | 拉取永不触碰 |

## 代码位置

- `WorkPanel/Sync/Jira/JiraClient.swift`——HTTP + JSON 解码(输入 jql,输出强类型 `JiraIssue` 数组),不碰 SwiftData
- `WorkPanel/Sync/Jira/JiraPullService.swift`——合并规则主体,依赖注入 ModelContext 与 client(便于测试:client 用协议抽象,测试注入固定 JSON)
- `AppSettings.swift`——新键
- `UI/Settings/SettingsView.swift`——Jira 区块
- denylist 挂钩点:`TodoStore.delete`(本地删除收敛点,唯一入口)
- 新建任务带 `"jira"` 标签后调用 `TagStore.reconcileFromTasks()`(与 LAN merge 的标签注册保持一致)

## 测试(WorkPanelTests)

- `JiraClient` 解析:search/jql 响应 fixture(nextPageToken 分页、ADF 提取、字段缺失容错)
- 合并规则逐条:新建、无变化跳过、远端更新、本地改过则本地优先、闭单传播(结果内关闭 + 二段查询关闭)、本地完成不复活、denylist 跳过插入、同 key 多条取最早
- 优先级/截止日映射边界
- 网络错误/401 不产生部分写入(先解码全部,再一次性应用)

## 已知限制(接受)

- **多机各自配置拉取可能重复**:两台机器都配置 Jira 拉取时,同一 issue 会产生不同 UUID 的两条,导入/导出合并后并存,拉取只更新较早一条。建议只在一台机器配置拉取;不做自动去重合并
- JQL 截断在 250 条;超大结果集不保证全量
- description 富文本信息丢失(纯文本提取)
- API Token 明文存 UserDefaults(与现有密钥一致,沙盒内接受)
