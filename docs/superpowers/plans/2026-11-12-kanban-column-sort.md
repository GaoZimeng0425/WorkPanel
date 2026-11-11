# 看板列排序 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 看板每个用户自定义列可持久选择排序方式(手动/优先级/截止日期/创建时间/标题),设置随列同步。

**Architecture:** 新增纯枚举 `ColumnSortOption` 承载排序规则(比较器内显式 boardOrder 决胜,不依赖排序稳定性);`BoardColumn` 加可选 `sortRaw` 持久化并进 `SyncColumnDTO`(optional 字段向后兼容,旧文档回退手动);`KanbanLensView` 列菜单加排序小节并按列排序显示。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData;测试用 Swift Testing(`import Testing`)。

**Spec:** `docs/superpowers/specs/2026-11-12-kanban-column-sort-design.md`

## Global Constraints

- 测试只跑单元包,禁止任何 e2e/UI 测试:
  `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`
- 单测风格:Swift Testing(`@Test`/`#expect`)、`@testable import WorkPanel`、`@MainActor` struct、中文用例名(参照 `WorkPanelTests/TaskFilterTests.swift` 等)。
- UI 文案中文:手动/优先级/截止日期/创建时间/标题。
- 提交用 conventional commits(`feat(board): …` / `test(board): …`)。
- 工程为 Xcode 16 文件系统同步分组(objectVersion 77):新建 `.swift` 放进 `WorkPanel/` 或 `WorkPanelTests/` 即自动入编译,不改 pbxproj。
- 匹配周边代码风格:中文文档注释、无多余抽象(AGENTS.md「Simplicity First / Surgical Changes」)。

## Review Focus

1. **旧数据回退**:`sortRaw` 为 nil(旧库行)或未知字符串(未来版本)必须回退手动,不得崩或排错 — Task 1/2 测试 `from(raw:)` 与 `BoardColumn.sort`。
2. **平局次序**:排序键相等时按 boardOrder 决胜(排序列内拖拽才有可预测效果)— Task 1 每条规则的平局断言。
3. **无截止日期**:deadline 排序下无截止任务殿后,而非 `nil` 比较被排到最前 — Task 1 测试。
4. **旧同步文档兼容**:缺 `sortRaw` 键的旧 JSON 必须能解出(optional 字段),否则整个 SyncDocument 解码失败、同步全挂 — Task 2 用旧格式 JSON 字面量解码测试。
5. **排序列内拖拽**:拖拽只改 boardOrder(平局次序),不破坏排序显示;跨列拖入照常追加 — 规则层由平局测试钉住,UI 行为用户手动确认。

---

### Task 1: ColumnSortOption 枚举与排序规则

**Files:**
- Create: `WorkPanel/Models/ColumnSortOption.swift`
- Test: `WorkPanelTests/ColumnSortOptionTests.swift`

**Interfaces:**
- Consumes: `TodoTask`(`priorityRaw`、`deadline: Date?`、`createdAt: Date`、`boardOrder: Int`)。
- Produces(Task 2/3 依赖,签名钉死):

```swift
enum ColumnSortOption: String, CaseIterable, Identifiable {
    case manual, priority, deadline, createdAt, title
    var id: String { rawValue }
    var label: String                    // 手动/优先级/截止日期/创建时间/标题
    static func from(raw: String?) -> ColumnSortOption   // nil/未知 → .manual
    func sorted(_ tasks: [TodoTask]) -> [TodoTask]
}
```

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/ColumnSortOptionTests.swift`,构造 `TodoTask`(用 `boardOrder:` 入参)覆盖:

- `manual 按 boardOrder 升序`
- `priority 高在前,平局按 boardOrder`
- `deadline 近的在前,无截止殿后,平局按 boardOrder`
- `createdAt 新的在前,平局按 boardOrder`
- `title localizedStandard 升序,平局按 boardOrder`(如 "任务10" < "任务2" 按 localizedStandard)
- `from raw nil 或未知字符串回退 manual`

断言用 `#expect(sorted.map(\.title) == [...])` 形式。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ColumnSortOptionTests CODE_SIGNING_ALLOWED=NO`
Expected: 编译失败,`cannot find 'ColumnSortOption' in scope`。

- [ ] **Step 3: 实现 `WorkPanel/Models/ColumnSortOption.swift`**

比较器末尾统一 `boardOrder` 决胜(不依赖 sorted 稳定性):

```swift
private func compare(_ a: TodoTask, _ b: TodoTask, _ key: (TodoTask, TodoTask) -> Bool?) -> Bool {
    if let r = key(a, b) { return r }
    return a.boardOrder < b.boardOrder
}
```

各键:priority → `$0.priorityRaw > $1.priorityRaw`;deadline → 四象限(nil 殿后,有值比小);createdAt → `$0.createdAt > $1.createdAt`(新的在前);title → `localizedStandard`。`manual` 直接 `sorted { $0.boardOrder < $1.boardOrder }`。

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令。Expected: PASS(6 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Models/ColumnSortOption.swift WorkPanelTests/ColumnSortOptionTests.swift
git commit -m "feat(board): add ColumnSortOption with per-rule tiebreak"
```

---

### Task 2: BoardColumn 持久化 + 同步 DTO + BoardStore.setSort

**Files:**
- Modify: `WorkPanel/Models/BoardColumn.swift`
- Modify: `WorkPanel/Store/BoardStore.swift`(rename 旁加一个方法)
- Modify: `WorkPanel/Sync/SyncDocument.swift:45-55`(`SyncColumnDTO`)
- Test: `WorkPanelTests/BoardColumnSortTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `ColumnSortOption.from(raw:)`。
- Produces(Task 3 依赖):

```swift
// BoardColumn
var sortRaw: String?                      // 新增持久属性,默认 nil
var sort: ColumnSortOption                // 计算属性 = ColumnSortOption.from(raw: sortRaw)

// BoardStore
func setSort(_ column: BoardColumn, to option: ColumnSortOption)   // 写 sortRaw(option == .manual 时写 nil)

// SyncColumnDTO
var sortRaw: String?                      // init(_:) / apply(to:) / makeModel() 全带上
```

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/BoardColumnSortTests.swift`(SwiftData 侧参照 `WorkPanelTests/BoardStoreTests.swift` 的 in-memory context 建法):

- `sortRaw nil 与未知字符串都回退 manual`(`BoardColumn(name:order:)` 后手改 `sortRaw`)
- `setSort 写入非手动选项后 sort 属性正确;切回 manual 时 sortRaw 为 nil`(走 `BoardStore`)
- `SyncColumnDTO 往返`:encode→decode 后 `sortRaw` 一致,`apply(to:)` 后模型一致
- `旧格式文档缺 sortRaw 键可解码`:手写旧 JSON 字面量 `{"id":…,"name":…,"order":0,"modifiedAt":…}`(用 `SyncDocument.encoder/decoder` 的 iso8601 日期格式),decode 后 `sortRaw == nil`

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardColumnSortTests CODE_SIGNING_ALLOWED=NO`
Expected: 编译失败,`BoardColumn` 无 `sort` 成员 / DTO 无 `sortRaw`。

- [ ] **Step 3: 实现三处修改**

- `BoardColumn`:`var sortRaw: String? = nil` 持久属性 + 计算属性 `var sort: ColumnSortOption { ColumnSortOption.from(raw: sortRaw) }`(SwiftData 对新增 optional 属性自动轻量迁移)。
- `BoardStore.setSort`:`column.sortRaw = option == .manual ? nil : option.rawValue`(一行,注释中文)。
- `SyncColumnDTO`:四成员同步加 `sortRaw`(optional,decode 缺键自动 nil,schemaVersion 不动)。

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令。Expected: PASS(4 个用例)。

- [ ] **Step 5: 全量单元包回归**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS(含既有全部用例)。

- [ ] **Step 6: 提交**

```bash
git add WorkPanel/Models/BoardColumn.swift WorkPanel/Store/BoardStore.swift WorkPanel/Sync/SyncDocument.swift WorkPanelTests/BoardColumnSortTests.swift
git commit -m "feat(board): persist per-column sort option and sync it"
```

---

### Task 3: 看板 UI — 列内按排序显示 + 列菜单排序小节

**Files:**
- Modify: `WorkPanel/UI/Board/KanbanLensView.swift`

**Interfaces:**
- Consumes: `column.sort.sorted(_:)`(Task 1/2)、`BoardStore.setSort(_:to:)`(Task 2)。

- [ ] **Step 1: 列内显示排序**

`activeTasks(in:)`(KanbanLensView.swift:31-34)在 filter 后改调 `column.sort.sorted(...)`(替代 `.sorted { $0.boardOrder < $1.boardOrder }`)。归档列 `archivedTasks` 不动。

- [ ] **Step 2: 列菜单加「排序」小节**

`columnActionsPopover(for:)`(KanbanLensView.swift:195-212)在「重命名」上方加小节标题「排序」+ `ForEach(ColumnSortOption.allCases)` 5 行:当前项显示 checkmark,点击 `store.setSort(column, to: option); try? context.saveTracking(); actionColumnID = nil`。行样式复用 `columnActionRow`,标题文案用 `option.label`,当前项加 `Image(systemName: "checkmark")`(在 label 前或右侧,与现有菜单视觉一致即可)。

- [ ] **Step 3: 编译 + 全量单元包回归**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`
Expected: 编译通过,PASS(本任务无新单测;排序逻辑已由 Task 1/2 钉住,UI 行为用户手动确认)。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/Board/KanbanLensView.swift
git commit -m "feat(board): column menu to pick sort option and sort cards"
```

- [ ] **Step 5: 用户手动确认**

用户在部署的 app 里:切某列到「优先级」→ 卡片按优先级排;平局拖拽换位生效;跨列拖入照常;重开 app 设置保留;旧库列默认手动。
