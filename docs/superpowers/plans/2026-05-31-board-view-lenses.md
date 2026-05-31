# 看板多透镜视图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在看板标题栏加 tab 切换器,把同一批活动任务用 看板 / 四象限 / 今日 / 优先级 四种透镜展示。

**Architecture:** `BoardView` 变为「外壳(标题栏 + tab + 按模式分发)」,四个透镜各自独立成 view,共用 `LensCard`。象限/今日只读(点击进编辑器),看板/优先级可拖拽。新增 `TodoTask.urgencyOverride` 三态字段,紧急度默认由 `deadline` 推导、可由编辑器 token 覆盖。

**Tech Stack:** SwiftUI + SwiftData,Swift Testing(`import Testing`),xcodebuild。

参考 spec:`docs/superpowers/specs/2026-05-31-board-view-lenses-design.md`

## 命令约定

- 跑某个测试套件:
  `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/<Suite> 2>&1 | tail -25`
- 只编译(视图任务用):
  `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `WorkPanel/Models/TodoTask.swift` | 改 | 加 `urgencyOverride` + `isImportant` + `isUrgent(asOf:)` + init 参数 |
| `WorkPanel/Models/BoardViewMode.swift` | 建 | 透镜模式枚举(label + SF Symbol) |
| `WorkPanel/Parsing/InputParser.swift` | 改 | `ParsedInput.urgencyOverride` + 紧急 token 映射 |
| `WorkPanel/Parsing/CaptureDraft.swift` | 改 | 合并 `urgencyOverride`(缺省即保留) |
| `WorkPanel/Store/TodoStore.swift` | 改 | `add` 透传 `urgencyOverride` |
| `WorkPanel/Store/BoardStore.swift` | 改 | `setPriority` |
| `WorkPanel/UI/TaskEditorView.swift` | 改 | 编辑态灌入/写回 `urgencyOverride`;TokenStrip 紧急 chip |
| `WorkPanel/UI/Theme.swift` | 改 | `quadrant(important:urgent:)` 语义色 |
| `WorkPanel/UI/LensCard.swift` | 建 | 透镜共用卡片(点击编辑/完成/删除;draggable 可选) |
| `WorkPanel/UI/KanbanLensView.swift` | 建 | 现有看板列布局迁出(行为不变) |
| `WorkPanel/UI/MatrixLensView.swift` | 建 | 2×2 象限(只读) |
| `WorkPanel/UI/TodayLensView.swift` | 建 | 今日列表(只读) |
| `WorkPanel/UI/PriorityLensView.swift` | 建 | 高/中/低 三列(可拖拽) |
| `WorkPanel/UI/BoardView.swift` | 改 | 外壳:标题栏 + tab + 分发 |
| `WorkPanel/Store/AppSettings.swift` | 改 | `boardViewMode` 键 + 默认值 |

新文件需在 Xcode target `WorkPanel` 里 membership 勾选(用 Xcode 新建文件或确认 `WorkPanel.xcodeproj` 已包含;`pbxproj` 用文件夹引用时自动纳入,否则手动添加 target membership)。

---

### Task 1: `TodoTask` 紧急/重要维度

**Files:**
- Modify: `WorkPanel/Models/TodoTask.swift`
- Test: `WorkPanelTests/TodoTaskTests.swift`

- [ ] **Step 1: 写失败测试**(追加到 `TodoTaskTests` struct 末尾,第 36 行 `}` 之前)

```swift
    @Test func isImportantFollowsPriority() {
        #expect(TodoTask(title: "a", priority: .high).isImportant)
        #expect(TodoTask(title: "a", priority: .medium).isImportant)
        #expect(!TodoTask(title: "a", priority: .low).isImportant)
    }

    @Test func isUrgentDerivesFromDeadlineWhenNoOverride() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(!TodoTask(title: "无截止").isUrgent(asOf: now))
        #expect(TodoTask(title: "1小时后", deadline: now.addingTimeInterval(3600)).isUrgent(asOf: now))
        #expect(TodoTask(title: "已逾期", deadline: now.addingTimeInterval(-3600)).isUrgent(asOf: now))
        #expect(!TodoTask(title: "72小时后", deadline: now.addingTimeInterval(72 * 3600)).isUrgent(asOf: now))
    }

    @Test func urgencyOverrideWinsOverDeadline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(TodoTask(title: "无截止但强制紧急", urgencyOverride: true).isUrgent(asOf: now))
        #expect(!TodoTask(title: "逾期但强制不紧急", deadline: now.addingTimeInterval(-3600),
                          urgencyOverride: false).isUrgent(asOf: now))
    }
```

需要在文件顶部确保 `import Foundation`(`TodoTaskTests` 当前只 import Testing/SwiftData;`Date` 来自 Foundation,SwiftData 已传递导入,如编译报缺失再加 `import Foundation`)。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoTaskTests 2>&1 | tail -25`
Expected: 编译失败(`isImportant`/`isUrgent`/`urgencyOverride` 未定义)。

- [ ] **Step 3: 实现**

在 `TodoTask.swift` 的属性区加字段(放在 `var boardOrder: Int` 之后,第 18 行后):

```swift
    var urgencyOverride: Bool?
```

在 `priority`/`recurrence` 计算属性之后(第 27 行 `}` 之后)加:

```swift
    static let urgentWindow: TimeInterval = 48 * 3600   // 48 小时内(含逾期)视为紧急

    var isImportant: Bool { priority != .low }          // 高/中 = 重要

    func isUrgent(asOf now: Date = .now) -> Bool {
        if let o = urgencyOverride { return o }
        guard let d = deadline else { return false }
        return d <= now.addingTimeInterval(Self.urgentWindow)
    }
```

把 init 改为带 `urgencyOverride` 参数(整段替换第 29-51 行的 init):

```swift
    init(title: String,
         notes: String = "",
         deadline: Date? = nil,
         priority: Priority = .medium,
         tags: [String] = [],
         recurrence: RecurrenceRule? = nil,
         urgencyOverride: Bool? = nil,
         createdAt: Date = .now,
         columnID: UUID? = nil,
         boardOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.deadline = deadline
        self.priorityRaw = priority.rawValue
        self.tags = tags
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = createdAt
        self.snoozedUntil = nil
        self.recurrenceRaw = recurrence?.rawValue
        self.columnID = columnID
        self.boardOrder = boardOrder
        self.urgencyOverride = urgencyOverride
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoTaskTests 2>&1 | tail -25`
Expected: 全部 PASS(含新增 3 个)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Models/TodoTask.swift WorkPanelTests/TodoTaskTests.swift
git commit -m "feat: TodoTask urgencyOverride + isImportant/isUrgent(asOf:)"
```

---

### Task 2: 紧急 token 解析

**Files:**
- Modify: `WorkPanel/Parsing/InputParser.swift`
- Test: `WorkPanelTests/InputParserTests.swift`

- [ ] **Step 1: 写失败测试**(追加到 `InputParserTests`,在 `priorityTokens()` 之后)

```swift
    @Test func urgencyTokens() {
        #expect(parse("活儿 !紧急").urgencyOverride == true)
        #expect(parse("活儿 !urgent").urgencyOverride == true)
        #expect(parse("活儿 !不紧急").urgencyOverride == false)
        #expect(parse("活儿 !非紧急").urgencyOverride == false)
        #expect(parse("活儿").urgencyOverride == nil)
        #expect(parse("活儿 !紧急").title == "活儿")   // token 被吃掉,不进标题
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/InputParserTests 2>&1 | tail -25`
Expected: 编译失败(`urgencyOverride` 不是 `ParsedInput` 成员)。

- [ ] **Step 3: 实现**

`ParsedInput` 加字段(第 8 行 `recurrence` 之后):

```swift
    nonisolated var urgencyOverride: Bool? = nil
```

`InputParser` 加映射表(紧接 `priorityMap` 之后,第 21 行后):

```swift
    nonisolated private static let urgencyMap: [String: Bool] = [
        "!紧急": true, "!urgent": true,
        "!不紧急": false, "!非紧急": false,
    ]
```

在 `parse` 的 token 循环里,把优先级分支扩成同时认紧急(替换第 42-43 行的 `if let p = ...` 分支起始为):

```swift
            if let p = Self.priorityMap[token] {
                result.priority = p
            } else if let u = Self.urgencyMap[token] {
                result.urgencyOverride = u
            } else if token.hasPrefix("#"), token.count > 1 {
```

(即在 `priorityMap` 分支与 `#` 标签分支之间插入 `urgencyMap` 分支。)

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/InputParserTests 2>&1 | tail -25`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/InputParser.swift WorkPanelTests/InputParserTests.swift
git commit -m "feat: parse !紧急/!不紧急 token into ParsedInput.urgencyOverride"
```

---

### Task 3: CaptureDraft 合并 urgencyOverride

**Files:**
- Modify: `WorkPanel/Parsing/CaptureDraft.swift:22`
- Test: `WorkPanelTests/CaptureDraftTests.swift`

- [ ] **Step 1: 写失败测试**(追加到 `CaptureDraftTests`,在 `emptyTextYieldsEmptyTitleAndNotes()` 之前)

```swift
    @Test func urgencyTokenSetsOverride() {
        let r = resolve("改标题 !紧急")
        #expect(r.fields.urgencyOverride == true)
    }

    @Test func urgencyAbsenceKeepsBase() {
        var base = ParsedInput()
        base.urgencyOverride = true
        let r = resolve("改标题", base: base)        // 第一行无紧急 token
        #expect(r.fields.urgencyOverride == true)     // 保留
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/CaptureDraftTests 2>&1 | tail -25`
Expected: FAIL —— `urgencyTokenSetsOverride` 拿到 `nil`(resolve 未透传),`urgencyAbsenceKeepsBase` 同样失败。

- [ ] **Step 3: 实现**

`CaptureDraft.resolve` 在 `fields.recurrence = ...` 之后(第 22 行后)加一行:

```swift
        fields.urgencyOverride = parsed.urgencyOverride ?? base.urgencyOverride   // 缺省即保留
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/CaptureDraftTests 2>&1 | tail -25`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/CaptureDraft.swift WorkPanelTests/CaptureDraftTests.swift
git commit -m "feat: CaptureDraft merges urgencyOverride (keep-on-absence)"
```

---

### Task 4: 编辑器贯通 urgencyOverride

**Files:**
- Modify: `WorkPanel/Store/TodoStore.swift:13-22`
- Modify: `WorkPanel/UI/TaskEditorView.swift`(init edit 分支、save edit 分支、TokenStrip)
- Test: `WorkPanelTests/TodoStoreTests.swift`

- [ ] **Step 1: 写失败测试**

`TodoStoreTests` 已有辅助 `makeStore() throws -> TodoStore`(内存容器)。追加测试(放进该 struct 末尾):

```swift
    @Test func addPropagatesUrgencyOverride() throws {
        let store = try makeStore()
        var parsed = ParsedInput()
        parsed.title = "强制紧急"
        parsed.urgencyOverride = true
        let task = store.add(parsed, notes: "")
        #expect(task.urgencyOverride == true)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoStoreTests 2>&1 | tail -25`
Expected: FAIL —— `task.urgencyOverride` 为 `nil`(add 未透传)。

- [ ] **Step 3: 实现 store**

`TodoStore.add` 的 `TodoTask(...)` 调用加 `urgencyOverride`(替换第 14-20 行的构造):

```swift
        let task = TodoTask(title: parsed.title,
                            notes: notes,
                            deadline: parsed.deadline,
                            priority: parsed.priority,
                            tags: parsed.tags,
                            recurrence: parsed.recurrence,
                            urgencyOverride: parsed.urgencyOverride,
                            createdAt: now)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoStoreTests 2>&1 | tail -25`
Expected: PASS。

- [ ] **Step 5: 编辑器灌入/写回 + chip**

`TaskEditorView.swift` init 的 `.edit(let task)` 分支,在 `b.recurrence = task.recurrence` 之后(第 41 行后)加:

```swift
            b.urgencyOverride = task.urgencyOverride
```

`save()` 的 `.edit(let existing)` 分支,在 `existing.recurrence = fields.recurrence` 之后(第 99 行后)加:

```swift
            existing.urgencyOverride = fields.urgencyOverride
```

`TokenStrip.chipTexts`(第 129-139 行),在 priority chip 之后插入紧急 chip(替换该计算属性为):

```swift
    private var chipTexts: [String] {
        var out: [String] = [Theme.priorityLabel(fields.priority)]
        if let u = fields.urgencyOverride {
            out.append(u ? "紧急" : "不紧急")
        }
        if let d = fields.deadline {
            out.append(d.formatted(date: .abbreviated, time: .shortened))
        }
        out += fields.tags.map { "#\($0)" }
        if let r = fields.recurrence {
            out.append(Theme.recurrenceLabel(r))
        }
        return out
    }
```

- [ ] **Step 6: 编译 + 手动验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED。
手动:运行 App,新建任务输入 `测试 !紧急`,TokenStrip 出现「紧急」chip;保存后重新打开该任务,仍显示「紧急」。

- [ ] **Step 7: 提交**

```bash
git add WorkPanel/Store/TodoStore.swift WorkPanel/UI/TaskEditorView.swift WorkPanelTests/TodoStoreTests.swift
git commit -m "feat: editor reads/writes urgencyOverride; token strip shows 紧急 chip"
```

---

### Task 5: `BoardStore.setPriority`

**Files:**
- Modify: `WorkPanel/Store/BoardStore.swift`
- Test: `WorkPanelTests/BoardStoreTests.swift`

- [ ] **Step 1: 写失败测试**(追加到 `BoardStoreTests` 末尾)

```swift
    @Test func setPriorityChangesPriority() throws {
        let store = try makeStore()
        let t = TodoTask(title: "T", priority: .low)
        store.context.insert(t)
        store.setPriority(t, to: .high)
        #expect(t.priority == .high)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25`
Expected: 编译失败(`setPriority` 未定义)。

- [ ] **Step 3: 实现**

`BoardStore.swift` 在 `setColumn` 之后、最后的 `}` 之前加:

```swift
    /// 优先级透镜拖拽落入某列时调用,仅改 priority(无序号语义)。
    func setPriority(_ task: TodoTask, to priority: Priority) {
        task.priority = priority
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/BoardStore.swift WorkPanelTests/BoardStoreTests.swift
git commit -m "feat: BoardStore.setPriority for priority lens drag"
```

---

### Task 6: `BoardViewMode` 枚举 + AppSettings 键

**Files:**
- Create: `WorkPanel/Models/BoardViewMode.swift`
- Modify: `WorkPanel/Store/AppSettings.swift`

- [ ] **Step 1: 建枚举**

`WorkPanel/Models/BoardViewMode.swift`:

```swift
import Foundation

/// 看板顶部 tab 的透镜模式。rawValue 用于 @AppStorage 持久化。
enum BoardViewMode: String, CaseIterable, Identifiable {
    case kanban, matrix, today, priority

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kanban:   "看板"
        case .matrix:   "象限"
        case .today:    "今日"
        case .priority: "优先级"
        }
    }
}
```

- [ ] **Step 2: AppSettings 加键与默认**

`AppSettings.Key` 枚举内加(在 `defaultPriority` 后):

```swift
        static let boardViewMode = "boardViewMode"
```

`registerDefaults()` 的字典里加一项(在 `defaultPriority` 行后):

```swift
            Key.boardViewMode: BoardViewMode.kanban.rawValue,
```

- [ ] **Step 3: 编译**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/Models/BoardViewMode.swift WorkPanel/Store/AppSettings.swift
git commit -m "feat: BoardViewMode enum + persisted boardViewMode default"
```

---

### Task 7: `Theme.quadrant` 语义色

**Files:**
- Modify: `WorkPanel/UI/Theme.swift`

- [ ] **Step 1: 加函数**

在 `Theme` 的 `priority(_:)` 之后(第 10 行后)加:

```swift
    nonisolated static func quadrant(important: Bool, urgent: Bool) -> Color {
        switch (important, urgent) {
        case (true, true):   priority(.high)   // 红
        case (true, false):  .blue
        case (false, true):  priority(.medium) // 橙
        case (false, false): priority(.low)    // 灰
        }
    }
```

(用字面量 `.blue` 而非 `static let deadline`,避免 nonisolated 函数访问 MainActor 静态属性的隔离问题。)

- [ ] **Step 2: 编译**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/Theme.swift
git commit -m "feat: Theme.quadrant semantic color for Eisenhower matrix"
```

---

### Task 8: `LensCard` 共用卡片

**Files:**
- Create: `WorkPanel/UI/LensCard.swift`

- [ ] **Step 1: 建视图**

`WorkPanel/UI/LensCard.swift`:

```swift
import SwiftUI
import SwiftData

/// 各透镜共用的任务卡片:点按打开编辑器、勾选完成、右键删除。
/// `draggable` 默认关闭;看板与优先级透镜显式开启。
struct LensCard: View {
    let task: TodoTask
    var draggable: Bool = false

    @Environment(\.modelContext) private var context
    private var todoStore: TodoStore { TodoStore(context: context) }
    private let scheduler = ReminderScheduler()

    var body: some View {
        let card = TaskCardView(task: task, onComplete: complete) { EmptyView() }
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .openTaskEditor,
                                                object: TaskEditorView.Mode.edit(task))
            }
            .contextMenu {
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task)
                    context.delete(task)
                    try? context.save()
                }
            }

        if draggable {
            card.draggable(task.id.uuidString)
        } else {
            card
        }
    }

    private func complete() {
        let next = todoStore.complete(task)
        try? context.save()
        scheduler.cancel(for: task)
        if let next { Task { await scheduler.schedule(for: next) } }
    }
}
```

- [ ] **Step 2: 编译**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED(LensCard 暂未被引用,只验证它自身可编译)。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/LensCard.swift
git commit -m "feat: shared LensCard (tap-to-edit / complete / delete; optional drag)"
```

---

### Task 9: 抽出 `KanbanLensView`

把现有 `BoardView` 的列布局原样迁到独立视图,行为不变。这是纯搬迁 + 用 `LensCard` 替换内联 card。

**Files:**
- Create: `WorkPanel/UI/KanbanLensView.swift`

- [ ] **Step 1: 建视图(内容迁自现 BoardView)**

`WorkPanel/UI/KanbanLensView.swift`:

```swift
import SwiftUI
import SwiftData

/// 看板透镜:用户自定义列 + 虚拟「归档」列,支持列间拖拽。
/// 内容迁自原 BoardView,行为不变。
struct KanbanLensView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    @State private var renaming: BoardColumn?
    @State private var renameText = ""
    @State private var addingColumn = false
    @State private var newColumnText = ""

    private var store: BoardStore { BoardStore(context: context) }
    private var todoStore: TodoStore { TodoStore(context: context) }
    private let scheduler = ReminderScheduler()

    private let columnWidth: CGFloat = 220

    private var validIDs: Set<UUID> { Set(columns.map(\.id)) }

    private func columnID(for task: TodoTask) -> UUID? {
        if let id = task.columnID, validIDs.contains(id) { return id }
        return columns.first?.id
    }

    private func activeTasks(in column: BoardColumn) -> [TodoTask] {
        tasks.filter { !$0.isCompleted && columnID(for: $0) == column.id }
             .sorted { $0.boardOrder < $1.boardOrder }
    }

    private var archivedTasks: [TodoTask] {
        tasks.filter { $0.isCompleted }
             .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { columnView($0) }
                archiveColumnView
                addColumnButton
            }
            .padding(12)
        }
        .alert("重命名列", isPresented: Binding(get: { renaming != nil },
                                              set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") {
                if let col = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.rename(col, to: renameText); try? context.save()
                }
                renaming = nil
            }
        }
        .alert("新建列", isPresented: $addingColumn) {
            TextField("名称", text: $newColumnText)
            Button("取消", role: .cancel) { newColumnText = "" }
            Button("添加") {
                let name = newColumnText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.addColumn(name: name); try? context.save() }
                newColumnText = ""
            }
        }
    }

    private func columnView(_ column: BoardColumn) -> some View {
        let items = activeTasks(in: column)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name).font(.subheadline).bold()
                Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .openTaskEditor,
                                                    object: TaskEditorView.Mode.create(columnID: column.id))
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .frame(width: 22)
                Menu {
                    Button("重命名") { renameText = column.name; renaming = column }
                    Button("删除", role: .destructive) { store.delete(column); try? context.save() }
                        .disabled(columns.count <= 1)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 22)
            }

            ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                LensCard(task: task, draggable: true)
                    .dropDestination(for: String.self) { dropped, _ in
                        handleDrop(dropped, into: column.id, at: index); return true
                    }
            }

            Button {
                NotificationCenter.default.post(name: .openTaskEditor,
                                                object: TaskEditorView.Mode.create(columnID: column.id))
            } label: {
                Text("+ 添加任务")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            handleDrop(dropped, into: column.id, at: items.count); return true
        }
    }

    private var archiveColumnView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("归档").font(.subheadline).bold()
                Text("\(archivedTasks.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
            }
            ForEach(archivedTasks) { task in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(task.title).strikethrough().foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .draggable(task.id.uuidString)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            handleArchiveDrop(dropped); return true
        }
    }

    private var addColumnButton: some View {
        Button { addingColumn = true } label: {
            Image(systemName: "plus").font(.title3).frame(width: 44, height: 60)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .frame(alignment: .top)
    }

    private func task(for uuidString: String) -> TodoTask? {
        guard let id = UUID(uuidString: uuidString) else { return nil }
        return tasks.first { $0.id == id }
    }

    private func handleDrop(_ dropped: [String], into columnID: UUID, at index: Int) {
        guard let s = dropped.first, let task = task(for: s) else { return }
        if task.isCompleted { todoStore.reopen(task) }
        store.move(task, to: columnID, at: index)
        try? context.save()
    }

    private func handleArchiveDrop(_ dropped: [String]) {
        guard let s = dropped.first, let task = task(for: s), !task.isCompleted else { return }
        let next = todoStore.complete(task)
        try? context.save()
        scheduler.cancel(for: task)
        if let next { Task { await scheduler.schedule(for: next) } }
    }
}
```

- [ ] **Step 2: 编译**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED(此时 BoardView 仍是旧实现,KanbanLensView 暂未被引用,只验证可编译)。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/KanbanLensView.swift
git commit -m "feat: extract KanbanLensView from BoardView (behavior unchanged)"
```

---

### Task 10: `BoardView` 改为外壳 + tab

把 BoardView 改成「标题栏 + 分段控件 + 按模式分发」。此后看板内容由 `KanbanLensView` 提供;象限/今日/优先级三个视图在 Task 11-13 落地,本任务先用占位让其编译运行。

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift`(整体替换)

- [ ] **Step 1: 替换 BoardView 整体实现**

`WorkPanel/UI/BoardView.swift` 全文替换为:

```swift
import SwiftUI
import SwiftData

/// 看板外壳:标题栏 + 透镜 tab 切换 + 按模式分发到各透镜视图。
struct BoardView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @AppStorage(AppSettings.Key.boardViewMode) private var modeRaw = BoardViewMode.kanban.rawValue

    private var store: BoardStore { BoardStore(context: context) }
    private var mode: BoardViewMode { BoardViewMode(rawValue: modeRaw) ?? .kanban }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { store.seedDefaultColumnsIfNeeded(); try? context.save() }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .kanban:   KanbanLensView()
        case .matrix:   MatrixLensView()
        case .today:    TodayLensView()
        case .priority: PriorityLensView()
        }
    }

    private var header: some View {
        HStack {
            Text("看板").font(.headline)
            Text("\(tasks.filter { !$0.isCompleted }.count) 项")
                .foregroundStyle(.secondary).font(.caption)
            Spacer()
            Picker("透镜", selection: $modeRaw) {
                ForEach(BoardViewMode.allCases) { m in
                    Text(m.label).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            Text("esc 收起").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
```

- [ ] **Step 2: 加三个临时占位视图让其编译**

在 `BoardView.swift` 文件末尾(临时,Task 11-13 会各自移到独立文件并删除这里的占位)加:

```swift
// MARK: - 临时占位(Task 11-13 替换为独立文件实现)
struct MatrixLensView: View { var body: some View { Color.clear } }
struct TodayLensView: View { var body: some View { Color.clear } }
struct PriorityLensView: View { var body: some View { Color.clear } }
```

- [ ] **Step 3: 编译 + 手动验证看板回归**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED。
手动:运行 App 打开看板 —— 标题栏出现 4 段分段控件;选「看板」时列、拖拽、新建/重命名/删除列、归档拖拽全部如旧;切到其它三段为空白;关闭重开后停留在上次所选 tab。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat: BoardView shell with lens tab switcher + placeholders"
```

---

### Task 11: `MatrixLensView` 四象限

**Files:**
- Create: `WorkPanel/UI/MatrixLensView.swift`
- Modify: `WorkPanel/UI/BoardView.swift`(删占位 `MatrixLensView`)

- [ ] **Step 1: 建视图**

`WorkPanel/UI/MatrixLensView.swift`:

```swift
import SwiftUI
import SwiftData

/// 艾森豪威尔四象限(只读):按 (重要, 紧急) 把活动任务分到 4 格,点击卡片走编辑器。
/// 象限标题已自述两轴(如「重要 · 紧急」),故不再单独画边轴标签。
struct MatrixLensView: View {
    @Query private var tasks: [TodoTask]

    private var active: [TodoTask] { tasks.filter { !$0.isCompleted } }

    private func bucket(important: Bool, urgent: Bool) -> [TodoTask] {
        active.filter { $0.isImportant == important && $0.isUrgent() == urgent }
              .sorted { $0.boardOrder < $1.boardOrder }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                quadrant(important: true,  urgent: true,  action: "马上做")
                quadrant(important: true,  urgent: false, action: "计划做")
            }
            HStack(spacing: 10) {
                quadrant(important: false, urgent: true,  action: "尽快处理")
                quadrant(important: false, urgent: false, action: "有空再说")
            }
        }
        .padding(12)
    }

    private func quadrant(important: Bool, urgent: Bool, action: String) -> some View {
        let items = bucket(important: important, urgent: urgent)
        let color = Theme.quadrant(important: important, urgent: urgent)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title(important: important, urgent: urgent))
                    .font(.subheadline).bold().foregroundStyle(color)
                Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Text(action).font(.caption).foregroundStyle(.secondary)
            }
            Rectangle().fill(color.opacity(0.4)).frame(height: 1)
            ScrollView {
                VStack(spacing: 8) {
                    if items.isEmpty {
                        Text("空").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(items) { LensCard(task: $0) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func title(important: Bool, urgent: Bool) -> String {
        switch (important, urgent) {
        case (true, true):   "重要 · 紧急"
        case (true, false):  "重要 · 不紧急"
        case (false, true):  "不重要 · 紧急"
        case (false, false): "不重要 · 不紧急"
        }
    }
}
```

- [ ] **Step 2: 删占位**

在 `BoardView.swift` 末尾删掉这一行:

```swift
struct MatrixLensView: View { var body: some View { Color.clear } }
```

- [ ] **Step 3: 编译 + 手动验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED。
手动:切到「象限」—— 2×2 四格,每格顶部彩色圆点 + 彩色标题 + 计数 + 行动短语 + 同色细线;任务按 重要(高/中)× 紧急(48h 内/逾期 或 `!紧急`)落格;点卡片打开编辑器;编辑器里把优先级改低或加 `!不紧急`,关闭后该卡片移动到对应象限。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/MatrixLensView.swift WorkPanel/UI/BoardView.swift
git commit -m "feat: MatrixLensView (read-only Eisenhower matrix)"
```

---

### Task 12: `TodayLensView` 今日

**Files:**
- Create: `WorkPanel/UI/TodayLensView.swift`
- Modify: `WorkPanel/UI/BoardView.swift`(删占位 `TodayLensView`)

- [ ] **Step 1: 建视图**

`WorkPanel/UI/TodayLensView.swift`:

```swift
import SwiftUI
import SwiftData

/// 今日聚焦(只读):逾期 + 今日到期(按 deadline)的活动任务,按截止时间升序。
struct TodayLensView: View {
    @Query private var tasks: [TodoTask]

    private var items: [TodoTask] {
        let now = Date.now
        let cal = Calendar.current
        return tasks
            .filter { task in
                guard !task.isCompleted, let d = task.deadline else { return false }
                return cal.isDateInToday(d) || d < now
            }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if items.isEmpty {
                    Text("今日无到期任务 🎉")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    ForEach(items) { LensCard(task: $0) }
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(12)
        }
    }
}
```

- [ ] **Step 2: 删占位**

在 `BoardView.swift` 末尾删掉:

```swift
struct TodayLensView: View { var body: some View { Color.clear } }
```

- [ ] **Step 3: 编译 + 手动验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED。
手动:切到「今日」—— 只列出今日到期或逾期任务,按时间升序;无则显示空状态文案;点卡片打开编辑器;改截止到明天后,关闭刷新该卡片从今日列表消失。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/TodayLensView.swift WorkPanel/UI/BoardView.swift
git commit -m "feat: TodayLensView (overdue + due-today focus list)"
```

---

### Task 13: `PriorityLensView` 优先级

**Files:**
- Create: `WorkPanel/UI/PriorityLensView.swift`
- Modify: `WorkPanel/UI/BoardView.swift`(删占位 `PriorityLensView`)

- [ ] **Step 1: 建视图**

`WorkPanel/UI/PriorityLensView.swift`:

```swift
import SwiftUI
import SwiftData

/// 优先级透镜:高/中/低 三列,拖拽卡片到某列即设 priority。
struct PriorityLensView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]

    private var store: BoardStore { BoardStore(context: context) }

    private func items(_ p: Priority) -> [TodoTask] {
        tasks.filter { !$0.isCompleted && $0.priority == p }
             .sorted { $0.boardOrder < $1.boardOrder }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(.high)
            column(.medium)
            column(.low)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func column(_ p: Priority) -> some View {
        let list = items(p)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Theme.priority(p)).frame(width: 8, height: 8)
                Text(Theme.priorityLabel(p)).font(.subheadline).bold()
                Text("\(list.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
            }
            ForEach(list) { LensCard(task: $0, draggable: true) }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            guard let s = dropped.first, let id = UUID(uuidString: s),
                  let task = tasks.first(where: { $0.id == id }) else { return false }
            store.setPriority(task, to: p)
            try? context.save()
            return true
        }
    }
}
```

- [ ] **Step 2: 删占位**

在 `BoardView.swift` 末尾删掉:

```swift
struct PriorityLensView: View { var body: some View { Color.clear } }
```

(此时占位注释行可一并删除。)

- [ ] **Step 3: 编译 + 手动验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -8`
Expected: BUILD SUCCEEDED。
手动:切到「优先级」—— 高/中/低 三等宽列,任务按优先级归列;把一张卡片拖到另一列,其优先级随之改变(卡片左侧圆点变色);点卡片仍可打开编辑器。

- [ ] **Step 4: 全量测试回归**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -25`
Expected: 所有套件 PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/PriorityLensView.swift WorkPanel/UI/BoardView.swift
git commit -m "feat: PriorityLensView (drag to set priority)"
```

---

## Self-Review 检查清单(写计划者已核对)

- **spec 覆盖**:数据模型(T1)、紧急 token 链路 ParsedInput→Parser→CaptureDraft→编辑器/Store(T2-T4)、setPriority(T5)、BoardViewMode+持久化(T6)、Theme.quadrant(T7)、LensCard(T8)、四透镜(T9/T11/T12/T13)、外壳+tab(T10)——逐项有任务。
- **范围外项**(⌘1-4、手动聚焦字段、token 清回 nil)未排任务,符合 spec。
- **类型一致**:`urgencyOverride: Bool?`、`isUrgent(asOf:)`、`Theme.quadrant(important:urgent:)`、`BoardViewMode`、`setPriority(_:to:)`、`LensCard(task:draggable:)` 在各任务间命名一致。
- **已知偏离 spec(已在任务内说明)**:象限省略独立边轴标签,改由象限标题自述两轴(更简洁)。

## 与 spec 的一处实现取舍

spec 写「四周加轴标签」;计划改为象限标题自带两轴名(「重要 · 紧急」等),省掉冗余的边轴标签。若你更想要边轴标签,在执行 Task 11 前说一声。
```
