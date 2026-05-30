# 看板面板(Kanban Board Panel)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 WorkPanel 增加一个从屏幕底部上滑的看板面板,把任务按用户可自定义的阶段列(计划中/开发中/测试中…)+ 内置归档列展示,支持列间/列内拖拽。

**Architecture:** 看板是现有 `TodoTask` 数据的另一个视图。新增 `BoardColumn` 模型表示可自定义的活动列;`TodoTask` 增加 `columnID`(所在列)和 `boardOrder`(列内手动排序)。「归档」是 `isCompleted==true` 的虚拟列,不是数据库记录。逻辑集中在新的 `BoardStore`(TDD 覆盖),UI 在 `BoardView`,面板由 `BoardPanelController`(底部上滑 NSPanel)承载,经新快捷键 ⌘⌥K 唤起。

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppKit(NSPanel), KeyboardShortcuts(已集成), Swift Testing(`import Testing`)。

---

## 项目须知(执行前必读)

- **新文件自动入 target**:本项目用 `PBXFileSystemSynchronizedRootGroup`,把 `.swift` 放进 `WorkPanel/` 或 `WorkPanelTests/` 对应目录即被编译,**无需改 `.pbxproj`**。
- **测试命令**(macOS 应用):
  ```bash
  xcodebuild test -scheme WorkPanel -destination 'platform=macOS' \
    -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25
  ```
  期望末尾出现 `Test Suite 'BoardStoreTests' passed`。
- **整体编译**:
  ```bash
  xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
  ```
  期望末尾 `** BUILD SUCCEEDED **`。
- 测试风格参照现有 `WorkPanelTests/TodoStoreTests.swift`:`@MainActor struct`,内存 `ModelContainer(isStoredInMemoryOnly: true)`。

## 文件结构

| 文件 | 操作 | 职责 |
|---|---|---|
| `WorkPanel/Models/TodoTask.swift` | 改 | 增加 `columnID`、`boardOrder` 字段 |
| `WorkPanel/Models/BoardColumn.swift` | 建 | 列模型 |
| `WorkPanel/Store/BoardStore.swift` | 建 | 列 CRUD、播种、任务移列/重排 |
| `WorkPanelTests/BoardStoreTests.swift` | 建 | `BoardStore` 单元测试 |
| `WorkPanel/UI/BoardView.swift` | 建 | 看板 UI(列、卡片、拖拽、新建、列管理) |
| `WorkPanel/UI/BoardPanelController.swift` | 建 | 底部上滑 NSPanel |
| `WorkPanel/System/HotkeyManager.swift` | 改 | 新增 `toggleBoard` 快捷键(默认 ⌘⌥K) |
| `WorkPanel/UI/SettingsView.swift` | 改 | 看板快捷键录制器 |
| `WorkPanel/WorkPanelApp.swift` | 改 | Schema 加 `BoardColumn`、AppDelegate 接线看板面板 + 捕获落列 |

---

## Task 1: `TodoTask` 增加看板字段

**Files:**
- Modify: `WorkPanel/Models/TodoTask.swift`

- [ ] **Step 1: 增加字段与 init 参数**

在 `recurrenceRaw` 属性后增加两个存储属性(`TodoTask.swift:16` 之后):

```swift
    var columnID: UUID?
    var boardOrder: Int
```

在 `init` 参数列表末尾(`createdAt: Date = .now` 之后)增加:

```swift
         createdAt: Date = .now,
         columnID: UUID? = nil,
         boardOrder: Int = 0) {
```

在 init 体末尾(`self.recurrenceRaw = recurrence?.rawValue` 之后)增加:

```swift
        self.columnID = columnID
        self.boardOrder = boardOrder
```

- [ ] **Step 2: 编译确认**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`(SwiftData 轻量迁移:可选字段 + 有默认值,不破坏现有数据)。

- [ ] **Step 3: Commit**

```bash
git add WorkPanel/Models/TodoTask.swift
git commit -m "feat: add columnID/boardOrder to TodoTask for kanban"
```

---

## Task 2: `BoardColumn` 模型

**Files:**
- Create: `WorkPanel/Models/BoardColumn.swift`

- [ ] **Step 1: 创建模型文件**

`WorkPanel/Models/BoardColumn.swift`:

```swift
import Foundation
import SwiftData

@Model
final class BoardColumn {
    var id: UUID
    var name: String
    var order: Int

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
    }
}
```

- [ ] **Step 2: 编译确认**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WorkPanel/Models/BoardColumn.swift
git commit -m "feat: add BoardColumn model"
```

---

## Task 3: `BoardStore` — 播种(seeding)

**Files:**
- Create: `WorkPanel/Store/BoardStore.swift`
- Test: `WorkPanelTests/BoardStoreTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/BoardStoreTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct BoardStoreTests {
    private func makeStore() throws -> BoardStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, configurations: config)
        return BoardStore(context: ModelContext(container))
    }

    @Test func seedCreatesThreeColumnsWhenEmpty() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        try store.context.save()
        let cols = store.columns()
        #expect(cols.map(\.name) == ["计划中", "开发中", "测试中"])
        #expect(cols.map(\.order) == [0, 1, 2])
    }

    @Test func seedAssignsIncompleteTasksToFirstColumnInSortOrder() throws {
        let store = try makeStore()
        let low = TodoTask(title: "低", priority: .low)
        let high = TodoTask(title: "高", priority: .high)
        let done = TodoTask(title: "完成了"); done.isCompleted = true
        [low, high, done].forEach { store.context.insert($0) }

        store.seedDefaultColumnsIfNeeded()
        try store.context.save()

        let first = store.columns().first!
        #expect(high.columnID == first.id)
        #expect(low.columnID == first.id)
        #expect(done.columnID == nil)            // 已完成不分列
        #expect(high.boardOrder == 0)            // 高优先级排前(sortRule)
        #expect(low.boardOrder == 1)
    }

    @Test func seedDoesNothingWhenColumnsExist() throws {
        let store = try makeStore()
        store.context.insert(BoardColumn(name: "已有", order: 0))
        store.seedDefaultColumnsIfNeeded()
        #expect(store.columns().map(\.name) == ["已有"])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25
```
Expected: 编译失败(`cannot find 'BoardStore' in scope`)。

- [ ] **Step 3: 创建 `BoardStore` 实现播种**

`WorkPanel/Store/BoardStore.swift`:

```swift
import Foundation
import SwiftData

@MainActor
final class BoardStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func columns() -> [BoardColumn] {
        (try? context.fetch(
            FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.order)])
        )) ?? []
    }

    var firstColumn: BoardColumn? { columns().first }

    /// 库中没有任何列时,建三列并把现有未完成任务归入第一列。否则不动。
    func seedDefaultColumnsIfNeeded() {
        guard columns().isEmpty else { return }
        let created = ["计划中", "开发中", "测试中"].enumerated().map {
            BoardColumn(name: $1, order: $0)
        }
        created.forEach { context.insert($0) }
        guard let first = created.first else { return }

        let incomplete = ((try? context.fetch(FetchDescriptor<TodoTask>())) ?? [])
            .filter { !$0.isCompleted }
            .sorted(by: TaskFilter.sortRule)
        for (i, task) in incomplete.enumerated() {
            task.columnID = first.id
            task.boardOrder = i
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25
```
Expected: `Test Suite 'BoardStoreTests' passed`

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Store/BoardStore.swift WorkPanelTests/BoardStoreTests.swift
git commit -m "feat: BoardStore seeding (default columns + assign existing tasks)"
```

---

## Task 4: `BoardStore` — 列 CRUD(增/改名/重排/删)

**Files:**
- Modify: `WorkPanel/Store/BoardStore.swift`
- Test: `WorkPanelTests/BoardStoreTests.swift`

- [ ] **Step 1: 追加失败测试**

在 `BoardStoreTests` 结构体末尾(`seedDoesNothingWhenColumnsExist` 之后)追加:

```swift
    @Test func addColumnAppendsWithNextOrder() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.addColumn(name: "上线")
        #expect(col.order == 3)
        #expect(store.columns().map(\.name) == ["计划中", "开发中", "测试中", "上线"])
    }

    @Test func renameChangesName() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        store.rename(col, to: "待办")
        #expect(store.columns().first!.name == "待办")
    }

    @Test func reorderAssignsSequentialOrder() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()                 // [计划中, 开发中, 测试中]
        store.reorder([cols[2], cols[0], cols[1]]) // 测试中, 计划中, 开发中
        #expect(store.columns().map(\.name) == ["测试中", "计划中", "开发中"])
    }

    @Test func deleteReassignsTasksToFirstColumn() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()
        let task = TodoTask(title: "在第二列")
        task.columnID = cols[1].id
        store.context.insert(task)

        store.delete(cols[1])
        #expect(store.columns().count == 2)
        #expect(task.columnID == cols[0].id)       // 移到第一列
    }

    @Test func deleteIsNoOpWhenOnlyOneColumn() throws {
        let store = try makeStore()
        let only = store.addColumn(name: "唯一")
        store.delete(only)
        #expect(store.columns().count == 1)        // 不能删到 0 列
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25
```
Expected: 编译失败(`value of type 'BoardStore' has no member 'addColumn'`)。

- [ ] **Step 3: 实现列 CRUD**

在 `BoardStore` 的 `seedDefaultColumnsIfNeeded()` 方法之后追加:

```swift
    @discardableResult
    func addColumn(name: String) -> BoardColumn {
        let nextOrder = (columns().map(\.order).max() ?? -1) + 1
        let col = BoardColumn(name: name, order: nextOrder)
        context.insert(col)
        return col
    }

    func rename(_ column: BoardColumn, to name: String) {
        column.name = name
    }

    /// 按传入数组顺序重新赋 order(0,1,2,…)。
    func reorder(_ ordered: [BoardColumn]) {
        for (i, col) in ordered.enumerated() { col.order = i }
    }

    /// 删除列;列内任务移到第一列。至少保留一个活动列(只剩一列时不删)。
    func delete(_ column: BoardColumn) {
        let cols = columns()
        guard cols.count > 1, let target = cols.first(where: { $0.id != column.id })
        else { return }
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        for task in tasks where task.columnID == column.id {
            task.columnID = target.id
        }
        context.delete(column)
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25
```
Expected: `Test Suite 'BoardStoreTests' passed`

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Store/BoardStore.swift WorkPanelTests/BoardStoreTests.swift
git commit -m "feat: BoardStore column CRUD (add/rename/reorder/delete)"
```

---

## Task 5: `BoardStore` — 任务移列与列内重排

**Files:**
- Modify: `WorkPanel/Store/BoardStore.swift`
- Test: `WorkPanelTests/BoardStoreTests.swift`

- [ ] **Step 1: 追加失败测试**

在 `BoardStoreTests` 末尾追加:

```swift
    @Test func moveSetsColumnAndRenumbersBoardOrder() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()
        let a = TodoTask(title: "A"); a.columnID = cols[0].id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = cols[1].id; b.boardOrder = 0
        [a, b].forEach { store.context.insert($0) }

        store.move(a, to: cols[1].id, at: 0)       // A 插到第二列最前
        #expect(a.columnID == cols[1].id)
        #expect(a.boardOrder == 0)
        #expect(b.boardOrder == 1)                 // B 被顺延
    }

    @Test func moveWithinColumnReorders() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        let a = TodoTask(title: "A"); a.columnID = col.id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = col.id; b.boardOrder = 1
        let c = TodoTask(title: "C"); c.columnID = col.id; c.boardOrder = 2
        [a, b, c].forEach { store.context.insert($0) }

        store.move(c, to: col.id, at: 0)           // C 移到最前
        #expect([c.boardOrder, a.boardOrder, b.boardOrder] == [0, 1, 2])
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25
```
Expected: 编译失败(`has no member 'move'`)。

- [ ] **Step 3: 实现 move**

在 `BoardStore` 的 `delete(_:)` 之后追加:

```swift
    /// 把 task 放到目标列的第 index 位,并把该列未完成任务的 boardOrder 重排为 0,1,2,…
    func move(_ task: TodoTask, to columnID: UUID, at index: Int) {
        task.columnID = columnID
        var siblings = ((try? context.fetch(FetchDescriptor<TodoTask>())) ?? [])
            .filter { !$0.isCompleted && $0.columnID == columnID && $0.id != task.id }
            .sorted { $0.boardOrder < $1.boardOrder }
        let clamped = max(0, min(index, siblings.count))
        siblings.insert(task, at: clamped)
        for (i, t) in siblings.enumerated() { t.boardOrder = i }
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -25
```
Expected: `Test Suite 'BoardStoreTests' passed`

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Store/BoardStore.swift WorkPanelTests/BoardStoreTests.swift
git commit -m "feat: BoardStore task move/reorder with boardOrder renumber"
```

---

## Task 6: `BoardView` — 看板 UI

SwiftUI 视图无法单元测试,验证方式为编译通过 + Task 9 后手动验收。本任务一次性写出完整视图。

**Files:**
- Create: `WorkPanel/UI/BoardView.swift`

- [ ] **Step 1: 创建完整视图**

`WorkPanel/UI/BoardView.swift`:

```swift
import SwiftUI
import SwiftData

struct BoardView: View {
    let onClose: () -> Void

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
        return columns.first?.id          // nil 或失效 id 归第一列
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
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { columnView($0) }
                    archiveColumnView
                    addColumnButton
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { store.seedDefaultColumnsIfNeeded(); try? context.save() }
        .onKeyPress(.escape) { onClose(); return .handled }
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

    private var header: some View {
        HStack {
            Text("看板").font(.headline)
            Text("\(tasks.filter { !$0.isCompleted }.count) 项").foregroundStyle(.secondary).font(.caption)
            Spacer()
            Text("esc 收起").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 活动列

    private func columnView(_ column: BoardColumn) -> some View {
        let items = activeTasks(in: column)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name).font(.subheadline).bold()
                Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Menu {
                    Button("重命名") { renameText = column.name; renaming = column }
                    Button("删除", role: .destructive) { store.delete(column); try? context.save() }
                        .disabled(columns.count <= 1)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 22)
            }

            ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                card(task)
                    .dropDestination(for: String.self) { dropped, _ in
                        handleDrop(dropped, into: column.id, at: index); return true
                    }
            }

            addTaskField(column)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            handleDrop(dropped, into: column.id, at: items.count); return true
        }
    }

    private func addTaskField(_ column: BoardColumn) -> some View {
        AddTaskField { title in
            let parsed = InputParser().parse(title, now: .now)
            guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let task = TodoTask(title: parsed.title, deadline: parsed.deadline,
                                priority: parsed.priority, tags: parsed.tags,
                                recurrence: parsed.recurrence)
            task.columnID = column.id
            task.boardOrder = activeTasks(in: column).count
            context.insert(task)
            try? context.save()
            Task { await scheduler.schedule(for: task) }
        }
    }

    // MARK: - 归档列(虚拟)

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
                    Text(task.title).strikethrough().foregroundStyle(.secondary)
                        .lineLimit(1)
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

    // MARK: - 卡片

    private func card(_ task: TodoTask) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { complete(task) } label: { Image(systemName: "circle") }
                .buttonStyle(.borderless)
            Circle().fill(priorityColor(task.priority)).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 13)).lineLimit(2)
                HStack(spacing: 6) {
                    if let d = task.deadline {
                        Text(d.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(d < .now ? .red : .secondary)
                    }
                    if task.recurrence != nil { Image(systemName: "repeat") }
                    ForEach(task.tags, id: \.self) { Text("#\($0)").foregroundStyle(.blue) }
                }
                .font(.system(size: 10))
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .draggable(task.id.uuidString)
        .contextMenu {
            Button("删除", role: .destructive) {
                scheduler.cancel(for: task); context.delete(task); try? context.save()
            }
        }
    }

    // MARK: - 拖拽处理

    private func task(for uuidString: String) -> TodoTask? {
        guard let id = UUID(uuidString: uuidString) else { return nil }
        return tasks.first { $0.id == id }
    }

    private func handleDrop(_ dropped: [String], into columnID: UUID, at index: Int) {
        guard let s = dropped.first, let task = task(for: s) else { return }
        if task.isCompleted { todoStore.reopen(task) }   // 从归档拖回
        store.move(task, to: columnID, at: index)
        try? context.save()
    }

    private func handleArchiveDrop(_ dropped: [String]) {
        guard let s = dropped.first, let task = task(for: s), !task.isCompleted else { return }
        complete(task)
    }

    private func complete(_ task: TodoTask) {
        let next = todoStore.complete(task)
        try? context.save()
        scheduler.cancel(for: task)
        if let next { Task { await scheduler.schedule(for: next) } }
    }

    private func priorityColor(_ p: Priority) -> Color {
        switch p { case .high: .red; case .medium: .orange; case .low: .gray }
    }
}

/// 列底快速新建输入框。回车提交后清空。
private struct AddTaskField: View {
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("+ 添加任务", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .onSubmit { onSubmit(text); text = "" }
    }
}
```

- [ ] **Step 2: 编译确认**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat: BoardView (columns, cards, drag-drop, add task/column, rename/delete)"
```

---

## Task 7: `BoardPanelController` — 底部上滑面板

**Files:**
- Create: `WorkPanel/UI/BoardPanelController.swift`

- [ ] **Step 1: 创建面板控制器**

`WorkPanel/UI/BoardPanelController.swift`:

```swift
import AppKit
import SwiftUI

/// 无边框面板默认无法成为 key window;子类放开以便接收 Esc / 文本输入。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class BoardPanelController: NSObject {
    private var panel: NSPanel?
    private let height: CGFloat = 360
    private let margin: CGFloat = 16

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content())
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = visible.width - margin * 2
        let final = NSRect(x: visible.minX + margin, y: visible.minY + margin,
                           width: width, height: height)
        let start = final.offsetBy(dx: 0, dy: -(height + margin))
        panel.setFrame(start, display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        let target = panel.frame.offsetBy(dx: 0, dy: -(panel.frame.height + margin))
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { panel.orderOut(nil) })
    }

    func toggle<Content: View>(@ViewBuilder _ content: () -> Content) {
        if isVisible { hide() } else { show(content) }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false          // 失焦不自动消失
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
```

- [ ] **Step 2: 编译确认**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WorkPanel/UI/BoardPanelController.swift
git commit -m "feat: BoardPanelController (bottom slide-up NSPanel)"
```

---

## Task 8: 快捷键 + 设置 + 接线

**Files:**
- Modify: `WorkPanel/System/HotkeyManager.swift`
- Modify: `WorkPanel/UI/SettingsView.swift`
- Modify: `WorkPanel/WorkPanelApp.swift`

- [ ] **Step 1: 新增看板快捷键名与注册入口**

`WorkPanel/System/HotkeyManager.swift` —— 在 `toggleCapture` 定义之后(`HotkeyManager.swift:9` 处的扩展内)追加:

```swift
    static let toggleBoard = Self(
        "toggleBoard",
        default: .init(.k, modifiers: [.command, .option])
    )
```

并在 `enum HotkeyManager` 内,`register` 方法之后追加:

```swift
    static func registerBoard(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleBoard, action: handler)
    }
```

- [ ] **Step 2: 设置里加录制器**

`WorkPanel/UI/SettingsView.swift` —— 在现有捕获录制器(`SettingsView.swift:13`)之后追加一行:

```swift
                KeyboardShortcuts.Recorder("唤起看板面板：", name: .toggleBoard)
```

- [ ] **Step 3: Schema 注册 BoardColumn**

`WorkPanel/WorkPanelApp.swift` —— 修改 `Schema`(`WorkPanelApp.swift:6`):

```swift
        let schema = Schema([TodoTask.self, BoardColumn.self])
```

- [ ] **Step 4: AppDelegate 接线看板面板 + 捕获落列**

`WorkPanel/WorkPanelApp.swift` —— 在 `AppDelegate` 增加看板控制器属性(`private let panel = PanelController()` 那一行下面):

```swift
    private let board = BoardPanelController()
```

在 `applicationDidFinishLaunching` 内,`HotkeyManager.register { ... }` 之后追加:

```swift
        HotkeyManager.registerBoard { [weak self] in self?.toggleBoard() }
```

在 `toggleCapture()` 的 `onSave` 闭包里,把:

```swift
                    let task = store.add(parsed, notes: notes)
                    try? context.save()
```

替换为(新建任务落到第一列):

```swift
                    let task = store.add(parsed, notes: notes)
                    task.columnID = BoardStore(context: context).firstColumn?.id
                    try? context.save()
```

在 `toggleCapture()` 方法之后追加 `toggleBoard()`:

```swift
    private func toggleBoard() {
        if board.isVisible { board.hide(); return }
        board.show {
            BoardView(onClose: { [weak self] in self?.board.hide() })
                .modelContainer(SharedModel.container)
        }
    }
```

- [ ] **Step 5: 编译确认**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add WorkPanel/System/HotkeyManager.swift WorkPanel/UI/SettingsView.swift WorkPanel/WorkPanelApp.swift
git commit -m "feat: wire board hotkey (⌘⌥K), settings recorder, schema, capture-into-first-column"
```

---

## Task 9: 全量测试 + 手动验收

**Files:** 无(验证任务)

- [ ] **Step 1: 跑全部测试**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -25
```
Expected: 所有 suite 通过,含 `BoardStoreTests`、`TodoStoreTests` 等。

- [ ] **Step 2: 手动验收(启动 app)**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/WorkPanel-*/Build/Products/Debug/WorkPanel.app
```

逐项确认:
- 按 ⌘⌥K → 面板从屏幕底部上滑出现,铺满底部宽度。
- 出现「计划中 / 开发中 / 测试中 / 归档」+「+」加列按钮;现有未完成任务出现在「计划中」。
- 拖动卡片到另一列 → 卡片移动并停留(关闭再开仍在新列)。
- 拖卡片到「归档」→ 变为已完成;从归档拖回某列 → 恢复并落在该列。
- 列底输入「测试 明天17:00 !高 #验收」回车 → 新卡片出现在该列,带截止/优先级/标签。
- 列头「⋯」→ 重命名生效;删除非空列 → 任务移到「计划中」;只剩一列时删除按钮禁用。
- 「+」加列 → 新列出现。
- 按 Esc 或再按 ⌘⌥K → 面板下滑收起;点别处不会自动消失。
- 设置面板里能看到并修改「唤起看板面板」快捷键。

- [ ] **Step 3: 最终提交(如手动验收发现需微调,改完再提交)**

```bash
git add -A
git commit -m "test: verify kanban board end-to-end"
```

---

## Self-Review 备注

- **Spec 覆盖**:数据模型(Task 1-2)、播种(Task 3)、列 CRUD + 删列移任务 + 至少留一列(Task 4)、移列/列内重排(Task 5)、UI 含拖拽/列底新建/卡片操作/列管理/归档列排序(Task 6)、底部上滑面板 + 仅 Esc/快捷键收起(Task 7)、快捷键 ⌘⌥K + 设置 + Schema + 捕获落列(Task 8)、验收(Task 9)。均有对应任务。
- **类型一致**:`BoardStore` 的 `columns()` / `firstColumn` / `seedDefaultColumnsIfNeeded()` / `addColumn(name:)` / `rename(_:to:)` / `reorder(_:)` / `delete(_:)` / `move(_:to:at:)` 在 Task 3-5 定义,Task 6/8 使用名称一致。`onClose` 闭包贯穿 BoardView/AppDelegate 一致。
- **拖拽载荷**:统一用 `task.id.uuidString`(`String` Transferable),draggable 与 dropDestination 两端一致。
