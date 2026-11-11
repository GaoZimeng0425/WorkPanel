# MCP: Jira 读取 + 工具面收敛 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `list_jira_tasks` 读工具并在 `TaskDTO` 暴露 Jira 来源;`complete/reopen` 并入 `update_task`;删除 `snooze_task`。

**Architecture:** 改动全部在 MCP 层(`TaskDTO.swift`、`MCPToolHandlers.swift`、`MCPDispatcher.swift`)加对应单元测试;底层 `TodoStore` 不动。

**Tech Stack:** Swift 6 / SwiftData / Swift Testing(`@Test`/`#expect`)。

**Spec:** `docs/superpowers/specs/2026-11-11-mcp-jira-read-and-tool-merge-design.md`

## Global Constraints

- 测试只跑单元包:`xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`;任务内循环可加 `-only-testing:WorkPanelTests/MCPToolHandlersTests`(或 `MCPDispatcherTests`)收窄。
- 禁止 e2e/UI 测试。
- conventional commits,直接在 develop 上提交。

## Review Focus

1. **重复完成产生重复 next** — 已完成循环任务再发 `completed:true` 不得再插一条 next(幂等守卫)→ Task 2 测试。
2. **`list_jira_tasks` 混入本地任务** — 无 `jiraKey` 的任务不得出现 → Task 1 测试。
3. **`TaskDTO` 加字段破坏既有解码** — 既有 `decodeTask` 用例继续过(null 填充)→ Task 1/2 既有测试即回归。
4. **`completed` 过滤语义** — `list_jira_tasks` 的 `completed:true/false` 各自只留对应任务 → Task 1 测试。
5. **update_task 不传 completed 不得改变完成态** — 字段更新路径无副作用 → Task 2 测试。

---

### Task 1: `list_jira_tasks` + TaskDTO Jira 字段

**Files:**
- Modify: `WorkPanel/MCP/TaskDTO.swift`(TaskDTO 增 2 字段)
- Modify: `WorkPanel/MCP/MCPToolHandlers.swift`(路由 + `listJiraTasks`)
- Modify: `WorkPanel/MCP/MCPDispatcher.swift`(目录条目)
- Test: `WorkPanelTests/MCPToolHandlersTests.swift`、`WorkPanelTests/MCPDispatcherTests.swift`

**Interfaces:**
- Produces: `TaskDTO` 新增 `jiraKey: String?`、`jiraSyncedAt: String?`(init 从 task 映射,ISO-8601);工具名 `list_jira_tasks`,参数 `completed?: boolean`,返回 `[TaskDTO]` JSON 文本。工具总数 10 → 11。

- [ ] **Step 1: 写失败测试**

`MCPToolHandlersTests.swift` 增加(沿用 `makeHandlers`/`decodeTask` 惯例):

```swift
// MARK: - list_jira_tasks

@Test func listJiraTasksReturnsOnlyJiraSourced() async throws {
    let (h, ctx, _) = try makeHandlers()
    let local = TodoTask(title: "本地"); ctx.insert(local); try ctx.save()
    let jira = TodoTask(title: "JIRA-42 修 bug"); jira.jiraKey = "JIRA-42"
    jira.jiraSyncedAt = Date(timeIntervalSince1970: 1000)
    ctx.insert(jira); try ctx.save()

    let dtos = try JSONDecoder().decode([TaskDTO].self, from: Data(try await h.call("list_jira_tasks", [:]).utf8))
    #expect(dtos.count == 1)
    #expect(dtos[0].jiraKey == "JIRA-42")
    #expect(dtos[0].jiraSyncedAt == ISO8601Date.string(Date(timeIntervalSince1970: 1000)))
}

@Test func listJiraTasksFiltersByCompleted() async throws {
    let (h, ctx, _) = try makeHandlers()
    let open = TodoTask(title: "开着"); open.jiraKey = "A-1"; ctx.insert(open)
    let done = TodoTask(title: "完成"); done.jiraKey = "A-2"
    done.isCompleted = true; done.completedAt = .now
    ctx.insert(done); try ctx.save()

    let all = try JSONDecoder().decode([TaskDTO].self, from: Data(try await h.call("list_jira_tasks", [:]).utf8))
    let closed = try JSONDecoder().decode([TaskDTO].self, from: Data(try await h.call("list_jira_tasks", ["completed": true]).utf8))
    #expect(all.count == 2 && closed.count == 1 && closed[0].jiraKey == "A-2")
}

@Test func localTaskDTOSerializesNullJiraFields() async throws {
    let (h, ctx, _) = try makeHandlers()
    let t = TodoTask(title: "本地"); ctx.insert(t); try ctx.save()
    #expect(try decodeTask(try await h.call("get_task", ["id": .string(t.id.uuidString)])).jiraKey == nil)
}
```

`MCPDispatcherTests.swift`:`toolsListReturnsTenTools` 计数 10 → 11,加 `#expect(names.contains("list_jira_tasks"))`。

- [ ] **Step 2: 跑测试确认失败**

`xcodebuild test … -only-testing:WorkPanelTests/MCPToolHandlersTests`(见 Global Constraints)
Expected: FAIL — `Unknown tool: list_jira_tasks` / `jiraKey` 不存在。

- [ ] **Step 3: 实现**

`TaskDTO`:struct 加 `let jiraKey: String?`、`let jiraSyncedAt: String?`,init 里 `jiraKey = task.jiraKey`、`jiraSyncedAt = task.jiraSyncedAt.map(ISO8601Date.string)`。
`MCPToolHandlers.call` 路由加 `case "list_jira_tasks": return try listJiraTasks(args)`;实现:fetch 全量 → `filter { $0.jiraKey != nil }` → 可选 `completed` 过滤(照抄 `listTasks` 的过滤写法)→ `encode(tasks.map(dto))`。
`MCPDispatcher.tools`:目录加 `toolEntry("list_jira_tasks", "List tasks pulled from Jira (all, or filtered by completion).", ["completed": ["type": "boolean"]])`,放在 `list_columns` 之后。

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令,再跑 `-only-testing:WorkPanelTests/MCPDispatcherTests`。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/TaskDTO.swift WorkPanel/MCP/MCPToolHandlers.swift WorkPanel/MCP/MCPDispatcher.swift WorkPanelTests/MCPToolHandlersTests.swift WorkPanelTests/MCPDispatcherTests.swift
git commit -m "feat(mcp): add list_jira_tasks and expose jira origin on TaskDTO"
```

---

### Task 2: `complete`/`reopen` 并入 `update_task`

**Files:**
- Modify: `WorkPanel/MCP/MCPToolHandlers.swift`(`CompleteResult`→`UpdateResult`;`updateTask` 增 `completed`;删 `completeTask`/`reopenTask` 路由与方法)
- Modify: `WorkPanel/MCP/MCPDispatcher.swift`(目录:删 2 条,`update_task` 描述/schema 加 `completed`)
- Test: `WorkPanelTests/MCPToolHandlersTests.swift`、`WorkPanelTests/MCPDispatcherTests.swift`

**Interfaces:**
- Consumes: Task 1 后的 `TaskDTO`。
- Produces: `struct UpdateResult: Codable { let task: TaskDTO; let next: TaskDTO? }`(替换 `CompleteResult`);`update_task` 可选参数 `completed: boolean`,返回 `UpdateResult` JSON;工具总数 11 → 9。

- [ ] **Step 1: 改写失败测试**

`MCPToolHandlersTests.swift`:
- `completeTaskCancelsNotificationAndReturnsTask` → 调 `update_task` + `"completed": true`,解码 `UpdateResult`,断言不变(task.isCompleted、next nil、cancel 发生)。
- `completeRecurringSchedulesNext` → 同上改调用方式,断言不变(next 非空、next 已排提醒)。
- `reopenClearsCompletion` → `update_task` + `"completed": false`,断言 `isCompleted == false`。
- 新增幂等测试:

```swift
@Test func completingAlreadyCompletedTaskYieldsNoDuplicateNext() async throws {
    let (h, ctx, _) = try makeHandlers()
    let t = TodoTask(title: "日报", deadline: Date(timeIntervalSinceNow: 3600), recurrence: .daily)
    t.isCompleted = true; t.completedAt = .now
    ctx.insert(t); try ctx.save()

    let r = try JSONDecoder().decode(UpdateResult.self, from: Data(try await h.call("update_task", ["id": .string(t.id.uuidString), "completed": true]).utf8))
    #expect(r.next == nil)
    // 幂等:不得冒出第二条未完成的重复出现(有则为 1)
    #expect(try JSONDecoder().decode([TaskDTO].self, from: Data(try await h.call("list_tasks", ["completed": false]).utf8)).count == 0)
}
```

`MCPDispatcherTests.swift`:计数 11 → 9,加 `#expect(!names.contains("complete_task") && !names.contains("reopen_task"))`。

- [ ] **Step 2: 跑测试确认失败**

同 Task 1 Step 2。Expected: FAIL — `complete_task` Unknown tool / `CompleteResult` 不存在。

- [ ] **Step 3: 实现**

- `CompleteResult` 改名 `UpdateResult`(字段不变)。
- `call` 删 `case "complete_task"`/`case "reopen_task"`,改 `case "update_task": return try await updateTask(args)`。
- `updateTask`:字段更新照旧;末尾统一返回前处理 `completed`:
  - `args["completed"]?.boolValue == true` 且 `!task.isCompleted` → `let next = todo.complete(task)`,保存后 `scheduler.cancel(for: task)`、`if let next { await scheduler.schedule(for: next) }`,返回 `UpdateResult(task:, next:)`。
  - `== false` 且 `task.isCompleted` → `todo.reopen(task)`,落进通用尾部 `cancel + schedule`(与现有字段更新一致),返回 `UpdateResult(task:, next: nil)`。
  - 其余路径返回 `UpdateResult(task:, next: nil)`(既有字段更新走这里)。
- 目录:删 `complete_task`/`reopen_task` 两条;`update_task` schema 加 `"completed": ["type": "boolean", "description": "true completes (recurring tasks spawn the next occurrence), false reopens"]`,描述句尾注明返回 `{task, next}`。

- [ ] **Step 4: 跑测试确认通过**

同 Task 1 Step 4。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/MCPToolHandlers.swift WorkPanel/MCP/MCPDispatcher.swift WorkPanelTests/MCPToolHandlersTests.swift WorkPanelTests/MCPDispatcherTests.swift
git commit -m "refactor(mcp): fold complete/reopen into update_task with completed flag"
```

---

### Task 3: 删除 `snooze_task`

**Files:**
- Modify: `WorkPanel/MCP/MCPToolHandlers.swift`(删路由 + `snoozeTask` 方法)
- Modify: `WorkPanel/MCP/MCPDispatcher.swift`(删目录条目)
- Test: `WorkPanelTests/MCPToolHandlersTests.swift`、`WorkPanelTests/MCPDispatcherTests.swift`

**Interfaces:**
- Produces: 工具总数 9 → 8;`TodoStore.snooze`、`TaskDTO.snoozedUntil` 保留不动。

- [ ] **Step 1: 清理/改写测试**

- 删 `snoozeSetsSnoozeWithoutTouchingNotifications`。
- `dtoExposesSnoozedUntil` 不再借工具赋值:直接 `t.snoozedUntil = ISO8601Date.date(until)` 后 `get_task` 断言 `dto.snoozedUntil == until`。
- `MCPDispatcherTests.swift`:计数 9 → 8,加 `#expect(!names.contains("snooze_task"))`,测试名改为 `toolsListReturnsCatalog`(不再硬编码数字)。

- [ ] **Step 2: 跑测试确认失败(路由删除前)**

先只改测试:`xcodebuild … -only-testing:WorkPanelTests/MCPDispatcherTests`。Expected: FAIL(count 9 ≠ 8 / contains snooze_task)。

- [ ] **Step 3: 实现**

删 `case "snooze_task"` 路由、`snoozeTask` 方法、目录里 `snooze_task` 条目。

- [ ] **Step 4: 全量单元测试确认通过**

Global Constraints 的全量命令(收尾门槛)。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/MCPToolHandlers.swift WorkPanel/MCP/MCPDispatcher.swift WorkPanelTests/MCPToolHandlersTests.swift WorkPanelTests/MCPDispatcherTests.swift
git commit -m "refactor(mcp): drop unused snooze_task tool"
```

---

## Self-Review 结论

- Spec 四条设计点 → Task 1/2/3 全覆盖;`TodoStore` 不动符合非目标。
- 类型一致:`UpdateResult` 在 Task 2 定义并贯穿;`jiraKey/jiraSyncedAt` 命名与模型字段一致。
- Review Focus 5 条均有归属测试;比例:plan 与改动量相当。
