# 看板列排序·方向与 chip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 看板列排序支持升/降方向切换,列头用橘色 chip 常驻显示「依据 ↑/↓」,× 唯一清除入口。

**Architecture:** `ColumnSortOption` 增加方向参数(sorted(_:descending:),自然升序为基准、降序翻转主键、无截止恒殿后、boardOrder 平局不变);`BoardColumn.sortDescending` 持久化并随 `SyncColumnDTO` 同步;`KanbanLensView` 列头加 chip(本体=翻转方向、×=清除)、菜单去掉「手动」并加「方向」小节。视觉与交互以原型 `docs/prototypes/2026-11-12-column-sort-filter.html`(v1.3)为权威。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData;测试 Swift Testing。

**Spec:** `docs/superpowers/specs/2026-11-12-kanban-column-sort-design.md`(「二轮修订」节为本次依据)

## Global Constraints

- 测试只跑单元包,禁止 e2e/UI 测试:
  `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`
- 单测风格:Swift Testing、`@testable import WorkPanel`、`@MainActor`(app target 默认 MainActor 隔离,Task 1 v1 已确认必须)、中文用例名。
- UI 文案中文:升序/降序;chip 文案「依据名 ↑/↓」(arrow.up.arrow.down 系 SF Symbol 或原型箭头字符风格,以原型观感为准)。
- 匹配周边代码风格:中文文档注释、Simplicity First / Surgical Changes。
- 提交 conventional commits(`feat(board):` / `test(board):`)。
- Xcode 16 文件系统同步分组:新 .swift 自动入编译,不改 pbxproj。
- 橘色 = Theme.accentText 前景 + accentSoft 底(以原型 CSS 与 WorkPanel/UI/DesignSystem/ 实际 token 为准,实现前先读原型与 Theme)。

## Review Focus

1. **降序不破坏殿后与决胜**:deadline 降序时无截止仍殿后;所有规则两方向平局仍按 boardOrder 升序 — Task 1 测试钉。
2. **升序语义=自然序**:优先级升=低在前、创建时间升=旧在前(与 v1 常用方向相反的方向必须真翻转)— Task 1。
3. **旧同步文档缺 sortDescending 键安全**(v1 文档有 sortRaw 无 sortDescending,必须解出)— Task 2。
4. **换依据重置常用方向**:优先级→截止日期时方向从降翻到升 — Task 2。
5. **清除彻底回手动**:× 后 chip 消失、菜单零打勾、方向置灰、sortRaw nil、sortDescending false — Task 2/3。
6. **手动列头零排序控件**(不渲染 chip)— UI,用户手动确认;规则层由 Task 2 store 测试钉。

---

### Task 1: ColumnSortOption 方向支持

**Files:**
- Modify: `WorkPanel/Models/ColumnSortOption.swift`
- Test: `WorkPanelTests/ColumnSortOptionTests.swift`

**Interfaces:**
- Produces(Task 2/3 依赖):

```swift
// 新增;sorted(_:) 保留且行为不变(= 常用方向),既有 6 用例不动
func sorted(_ tasks: [TodoTask], descending: Bool) -> [TodoTask]
var preferredDescending: Bool          // priority/createdAt true;deadline/title false
```

- 升序=自然序:priorityRaw 升、deadline 近→远(无截止殿后)、createdAt 旧→新、title A→Z;
  降序仅翻转主键,无截止仍殿后,平局 boardOrder 决胜两方向不变。

- [ ] **Step 1: 写失败测试**(追加到 ColumnSortOptionTests,既有用例不改)
  - 每条规则(优先级/截止日期/创建时间/标题)补「升序」与「降序」两用例,断言 `sorted(tasks, descending:)` 的完整顺序(map(\.title) / map(\.boardOrder))
  - deadline 降序含「无截止殿后」断言;平局组在两个方向下都按 boardOrder
  - `preferredDescending` 四值断言
- [ ] **Step 2: 跑测试确认失败** — Run: `xcodebuild test … -only-testing:WorkPanelTests/ColumnSortOptionTests CODE_SIGNING_ALLOWED=NO`,Expected: 编译失败(缺 descending 参数/preferredDescending)
- [ ] **Step 3: 实现** — 比较器主键结果按 descending 翻转(nil 平局与 boardOrder 决胜不翻);`sorted(_:)` 委托 `sorted($0, descending: preferredDescending)`
- [ ] **Step 4: 跑测试确认通过**(既有 6 + 新增全过)
- [ ] **Step 5: 全量单元包回归 + 提交** `test(board): add sort direction to ColumnSortOption`

### Task 2: BoardColumn 方向持久化 + store + 同步

**Files:**
- Modify: `WorkPanel/Models/BoardColumn.swift`、`WorkPanel/Store/BoardStore.swift`、`WorkPanel/Sync/SyncDocument.swift`
- Test: `WorkPanelTests/BoardColumnSortTests.swift`

**Interfaces:**
- Consumes: `ColumnSortOption.preferredDescending`。
- Produces(Task 3 依赖):

```swift
// BoardColumn 新增持久属性(SwiftData 轻量迁移)
var sortDescending: Bool = false
// BoardStore
func setSort(_ column: BoardColumn, to option: ColumnSortOption)   // 非 manual:sortRaw + sortDescending = option.preferredDescending;manual:两者清(false)
func toggleSortDirection(_ column: BoardColumn)                    // manual 时 no-op;否则翻转 sortDescending
func clearSort(_ column: BoardColumn)                              // sortRaw = nil, sortDescending = false
// SyncColumnDTO 四成员带 sortDescending: Bool?(旧文档缺键 → nil → apply 落 false)
```

- [ ] **Step 1: 写失败测试**(追加):setSort 各依据方向=常用方向、手动清 false;toggle 翻转与手动 no-op;clear 彻底清;DTO 往返含 true/false;v1 旧 JSON(有 sortRaw 无 sortDescending)解码 nil 且 apply 后 false
- [ ] **Step 2: 确认失败**(编译错)
- [ ] **Step 3: 实现三处**(一行式 store 方法,中文注释;DTO optional 字段)
- [ ] **Step 4: 确认通过**
- [ ] **Step 5: 全量回归 + 提交** `feat(board): persist per-column sort direction and sync it`

### Task 3: 看板 UI — 列头 chip + 菜单方向小节

**Files:**
- Modify: `WorkPanel/UI/Board/KanbanLensView.swift`
- Reference(只读): `docs/prototypes/2026-11-12-column-sort-filter.html`(视觉/交互权威)、`WorkPanel/UI/DesignSystem/`

**Interfaces:**
- Consumes: `sorted(_:descending:)`、`preferredDescending`、`toggleSortDirection`、`clearSort`、`column.sortDescending`。

- [ ] **Step 1: 列内显示** — `activeTasks(in:)` 改 `column.sort.sorted(tasks, descending: column.sortDescending)`(manual 分支方向无意义,天然安全)
- [ ] **Step 2: 列头 chip** — `column.sort != .manual` 时在计数右侧、「+」左侧渲染:橘色 pill(accentText + accentSoft,10pt bold 圆角,hover 提亮)「label + ↑/↓箭头」+「×」;点本体 `store.toggleSortDirection(column)`、点 × `store.clearSort(column)`,各接 `try? context.saveTracking()`;列名加 lineLimit(1) 截断防挤
- [ ] **Step 3: 菜单** — 排序小节去掉「手动」(ColumnSortOption.allCases 过滤),保留打勾;其后加「方向」小节升/降两行(当前打勾,manual 时 disabled),点击 `store.setSort(column, to:)` 不动方向——方向行直接写 `column.sortDescending` + saveTracking(setSort 会重置方向,方向行不能用 setSort)
- [ ] **Step 4: 全量单元包回归 + 提交** `feat(board): column sort chip with direction toggle`
- [ ] **Step 5: 用户手动确认**(build.sh 部署后)
