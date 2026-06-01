# 统一任务编辑/创建 Popover 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 点击任务卡片弹出可编辑的详情 popover，创建与编辑共用同一表单，创建时可选状态（看板列）。

**Architecture:** 新增纯展示的字段布局 `TaskFormFields`，被 `TaskEditorView` 的编辑/创建两种模式复用；通过 `.taskEditPopover` 修饰符（点卡片）和 `CreateTaskButton`（点 `+`）触发。状态复用现有 `BoardColumn`——编辑/创建改状态都走新增的 `BoardStore.setColumn`，零数据结构改动。

**Tech Stack:** SwiftUI + SwiftData，Swift Testing（`import Testing` / `@Test` / `#expect`），Xcode 16（`PBXFileSystemSynchronizedRootGroup`——新文件放进 `WorkPanel/UI/` 自动进 target，无需改 `project.pbxproj`）。

**测试/构建命令：**
- 单测：`xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -30`
- 全量构建：`xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -20`

---

## 文件结构

| 文件 | 职责 | 动作 |
|---|---|---|
| `WorkPanel/Store/BoardStore.swift` | 加 `setColumn(_:to:)` | 修改 |
| `WorkPanelTests/BoardStoreTests.swift` | `setColumn` 的测试 | 修改 |
| `WorkPanel/UI/TaskFormFields.swift` | 创建/编辑共用的字段布局（纯展示） | 新建 |
| `WorkPanel/UI/TaskEditorView.swift` | 编辑/创建模式 + 触发修饰符/按钮 | 新建 |
| `WorkPanel/UI/TaskListView.swift` | 卡片点击编辑 + 列表 `+` 创建 | 修改 |
| `WorkPanel/UI/BoardView.swift` | 卡片点击编辑 + 列头 `+` 创建 | 修改 |

---

## Task 1: `BoardStore.setColumn(_:to:)`（TDD）

把任务的"状态"设为某看板列（追加到列末尾并重排 `boardOrder`）或清空（`columnID = nil`）。复用已测的 `move`。

**Files:**
- Modify: `WorkPanel/Store/BoardStore.swift`
- Test: `WorkPanelTests/BoardStoreTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WorkPanelTests/BoardStoreTests.swift` 最后一个 `}` 之前（第 131 行 `}` 之后、闭合 struct 的 `}` 之前）加入：

```swift
    @Test func setColumnAppendsToEndOfTargetColumnAndRenumbers() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()
        let a = TodoTask(title: "A"); a.columnID = cols[1].id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = cols[1].id; b.boardOrder = 1
        let mover = TodoTask(title: "M"); mover.columnID = cols[0].id; mover.boardOrder = 0
        [a, b, mover].forEach { store.context.insert($0) }

        store.setColumn(mover, to: cols[1].id)

        #expect(mover.columnID == cols[1].id)
        #expect([a.boardOrder, b.boardOrder, mover.boardOrder] == ([0, 1, 2] as [Int]))
    }

    @Test func setColumnToNilClearsStatus() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        let t = TodoTask(title: "T"); t.columnID = col.id; t.boardOrder = 3
        store.context.insert(t)

        store.setColumn(t, to: nil)

        #expect(t.columnID == nil)
    }

    @Test func setColumnToSameColumnIsNoOp() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        let a = TodoTask(title: "A"); a.columnID = col.id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = col.id; b.boardOrder = 1
        [a, b].forEach { store.context.insert($0) }

        store.setColumn(b, to: col.id)

        #expect([a.boardOrder, b.boardOrder] == ([0, 1] as [Int]))
    }
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -30`
Expected: 编译失败，`value of type 'BoardStore' has no member 'setColumn'`。

- [ ] **Step 3: 实现 `setColumn`**

在 `WorkPanel/Store/BoardStore.swift` 的 `move(_:to:at:)` 方法之后（第 81 行 `}` 之后、类闭合 `}` 之前）加入：

```swift
    /// 设置任务状态(所属看板列)。目标为某列时追加到该列末尾并重排;目标为 nil 时清空状态。
    func setColumn(_ task: TodoTask, to columnID: UUID?) {
        guard task.columnID != columnID else { return }
        if let columnID {
            move(task, to: columnID, at: .max)   // .max 经 move 内部 clamp 到末尾
        } else {
            task.columnID = nil
        }
    }
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests 2>&1 | tail -30`
Expected: 全部通过（含原有 BoardStore 测试 + 3 个新测试）。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/BoardStore.swift WorkPanelTests/BoardStoreTests.swift
git commit -m "feat: BoardStore.setColumn sets/clears task status column"
```

---

## Task 2: `TaskFormFields` 字段布局（纯展示）

创建/编辑共用的字段控件，仅绑定，不做持久化。

**Files:**
- Create: `WorkPanel/UI/TaskFormFields.swift`

- [ ] **Step 1: 新建文件**

写入 `WorkPanel/UI/TaskFormFields.swift`：

```swift
import SwiftUI

/// 创建 / 编辑任务共用的字段布局。仅负责字段控件,不做任何持久化。
struct TaskFormFields: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var deadline: Date?
    @Binding var priority: Priority
    @Binding var tags: [String]
    @Binding var recurrence: RecurrenceRule?
    @Binding var columnID: UUID?
    let columns: [BoardColumn]

    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, weight: .medium))

            VStack(alignment: .leading, spacing: 4) {
                Text("备注").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .frame(height: 60)
                    .font(.system(size: 13))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }

            Toggle("截止时间", isOn: hasDeadline)
            if deadline != nil {
                DatePicker("", selection: deadlineValue,
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }

            Picker("优先级", selection: $priority) {
                ForEach(Priority.allCases, id: \.self) { p in
                    Text(Theme.priorityLabel(p)).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Picker("重复", selection: $recurrence) {
                Text("无").tag(RecurrenceRule?.none)
                ForEach(RecurrenceRule.allCases, id: \.self) { r in
                    Text(Theme.recurrenceLabel(r)).tag(Optional(r))
                }
            }

            Picker("状态", selection: $columnID) {
                Text("无状态").tag(UUID?.none)
                ForEach(columns) { col in
                    Text(col.name).tag(Optional(col.id))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("标签").font(.caption).foregroundStyle(.secondary)
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 3) {
                                    Text("#\(tag)")
                                    Button { tags.removeAll { $0 == tag } } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.system(size: 11))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.tag.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.tag)
                            }
                        }
                    }
                }
                TextField("添加标签后回车", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addTags)
            }
        }
    }

    private var hasDeadline: Binding<Bool> {
        Binding(get: { deadline != nil },
                set: { deadline = $0 ? (deadline ?? defaultDeadline()) : nil })
    }
    private var deadlineValue: Binding<Date> {
        Binding(get: { deadline ?? defaultDeadline() },
                set: { deadline = $0 })
    }
    private func defaultDeadline() -> Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private func addTags() {
        let parts = newTag.split { $0 == " " || $0 == "," || $0 == "，" }.map(String.init)
        for p in parts where !p.isEmpty && !tags.contains(p) { tags.append(p) }
        newTag = ""
    }
}
```

- [ ] **Step 2: 编译确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`（`TaskFormFields` 暂无引用方，仅需编译通过）。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/TaskFormFields.swift
git commit -m "feat: TaskFormFields shared editor field layout"
```

---

## Task 3: `TaskEditorView` + 触发修饰符/按钮

编辑模式（绑定模型、实时生效、关闭时持久化并重排提醒）与创建模式（本地草稿、保存按钮/⌘↩ 落库）；以及 `.taskEditPopover` 修饰符和 `CreateTaskButton`。

**Files:**
- Create: `WorkPanel/UI/TaskEditorView.swift`

- [ ] **Step 1: 新建文件**

写入 `WorkPanel/UI/TaskEditorView.swift`：

```swift
import SwiftUI
import SwiftData

/// 创建 / 编辑任务的统一弹窗内容。两种模式共用 `TaskFormFields`。
struct TaskEditorView: View {
    enum Mode {
        case edit(TodoTask)
        case create(columnID: UUID?)
    }
    let mode: Mode

    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    var body: some View {
        Group {
            switch mode {
            case .edit(let task):
                EditEditor(task: task, columns: columns)
            case .create(let columnID):
                CreateEditor(initialColumnID: columnID, columns: columns)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// 编辑已存在任务:字段绑定到模型,改即生效;关闭时持久化并重排提醒。
private struct EditEditor: View {
    @Bindable var task: TodoTask
    let columns: [BoardColumn]

    @Environment(\.modelContext) private var context
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    var body: some View {
        TaskFormFields(
            title: $task.title,
            notes: $task.notes,
            deadline: $task.deadline,
            priority: $task.priority,
            tags: $task.tags,
            recurrence: $task.recurrence,
            columnID: Binding(get: { task.columnID },
                              set: { boardStore.setColumn(task, to: $0); try? context.save() }),
            columns: columns)
        .onDisappear {
            try? context.save()
            Task { await scheduler.schedule(for: task) }
        }
    }
}

/// 新建任务:本地草稿,保存按钮 / ⌘↩ 才落库。
private struct CreateEditor: View {
    let columns: [BoardColumn]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private var todoStore: TodoStore { TodoStore(context: context) }
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    @State private var title = ""
    @State private var notes = ""
    @State private var deadline: Date? = nil
    @State private var priority: Priority = .medium
    @State private var tags: [String] = []
    @State private var recurrence: RecurrenceRule? = nil
    @State private var columnID: UUID?

    init(initialColumnID: UUID?, columns: [BoardColumn]) {
        self.columns = columns
        _columnID = State(initialValue: initialColumnID)
    }

    var body: some View {
        VStack(spacing: 12) {
            TaskFormFields(
                title: $title, notes: $notes, deadline: $deadline,
                priority: $priority, tags: $tags, recurrence: $recurrence,
                columnID: $columnID, columns: columns)

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { save(); return .handled }
            return .ignored
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var parsed = ParsedInput()
        parsed.title = trimmed
        parsed.deadline = deadline
        parsed.priority = priority
        parsed.tags = tags
        parsed.recurrence = recurrence
        let task = todoStore.add(parsed, notes: notes)
        boardStore.setColumn(task, to: columnID)
        try? context.save()
        Task { await scheduler.schedule(for: task) }
        dismiss()
    }
}

/// 点击触发编辑 popover 的修饰符。每次应用持有独立的展示状态。
struct TaskEditPopover: ViewModifier {
    let task: TodoTask
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { show = true }
            .popover(isPresented: $show, arrowEdge: .trailing) {
                TaskEditorView(mode: .edit(task))
            }
    }
}

extension View {
    func taskEditPopover(_ task: TodoTask) -> some View {
        modifier(TaskEditPopover(task: task))
    }
}

/// 新建任务按钮:点击弹出创建 popover。columnID 预选状态(nil = 无状态)。
struct CreateTaskButton: View {
    let columnID: UUID?
    @State private var show = false

    var body: some View {
        Button { show = true } label: { Image(systemName: "plus.circle") }
            .buttonStyle(.borderless)
            .popover(isPresented: $show, arrowEdge: .bottom) {
                TaskEditorView(mode: .create(columnID: columnID))
            }
    }
}
```

- [ ] **Step 2: 编译确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`。
若报 `Task` 捕获 `task` 的并发告警，对照 `BoardView.complete`（第 219 行）/`TaskListView.complete`（第 146 行）现有同款写法——本仓库该写法可编译，无需改动。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/TaskEditorView.swift
git commit -m "feat: TaskEditorView with edit/create modes, tap-popover modifier, create button"
```

---

## Task 4: 接入 `TaskListView`（卡片点击编辑 + 列表 `+` 创建）

**Files:**
- Modify: `WorkPanel/UI/TaskListView.swift`（`header` 计算属性、`row(_:)` 方法）

- [ ] **Step 1: 卡片加编辑 popover**

把 `row(_:)`（第 106-122 行）末尾的闭合改为在 `TaskCardView { ... }` 之后挂修饰符。将：

```swift
    private func row(_ task: TodoTask) -> some View {
        TaskCardView(task: task, onComplete: { complete(task) }) {
            Menu {
                Button("推迟到明天") { snooze(task, days: 1) }
                Button("推迟到下周") { snooze(task, days: 7) }
                Divider()
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task)
                    store.delete(task); try? context.save()
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
    }
```

改为（仅在最外层闭合 `}` 前加一行 `.taskEditPopover(task)`）：

```swift
    private func row(_ task: TodoTask) -> some View {
        TaskCardView(task: task, onComplete: { complete(task) }) {
            Menu {
                Button("推迟到明天") { snooze(task, days: 1) }
                Button("推迟到下周") { snooze(task, days: 7) }
                Divider()
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task)
                    store.delete(task); try? context.save()
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .taskEditPopover(task)
    }
```

- [ ] **Step 2: 列表头加 `+` 创建按钮**

把 `header`（第 51-72 行）中标签 `Menu` 之后、HStack 闭合前加入 `CreateTaskButton`。将标签 Menu 块结尾：

```swift
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
```

改为：

```swift
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)

            CreateTaskButton(columnID: nil)
                .frame(width: 28)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
```

- [ ] **Step 3: 编译确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/TaskListView.swift
git commit -m "feat: list cards open edit popover; header + opens create popover"
```

---

## Task 5: 接入 `BoardView`（卡片点击编辑 + 列头 `+` 创建）

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift`（`columnView(_:)` 列头、`card(_:)` 方法）

- [ ] **Step 1: 看板卡片加编辑 popover**

把 `card(_:)`（第 186-194 行）：

```swift
    private func card(_ task: TodoTask) -> some View {
        TaskCardView(task: task, onComplete: { complete(task) }) { EmptyView() }
            .draggable(task.id.uuidString)
            .contextMenu {
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task); context.delete(task); try? context.save()
                }
            }
    }
```

改为（在 `.contextMenu { ... }` 之后加 `.taskEditPopover(task)`）：

```swift
    private func card(_ task: TodoTask) -> some View {
        TaskCardView(task: task, onComplete: { complete(task) }) { EmptyView() }
            .draggable(task.id.uuidString)
            .contextMenu {
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task); context.delete(task); try? context.save()
                }
            }
            .taskEditPopover(task)
    }
```

- [ ] **Step 2: 列头加 `+` 创建按钮（预选该列）**

把 `columnView(_:)` 列头 HStack（第 99-109 行）：

```swift
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
```

改为（在 `Spacer()` 之后、`Menu` 之前插入 `CreateTaskButton`）：

```swift
            HStack {
                Text(column.name).font(.subheadline).bold()
                Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                CreateTaskButton(columnID: column.id)
                    .frame(width: 22)
                Menu {
                    Button("重命名") { renameText = column.name; renaming = column }
                    Button("删除", role: .destructive) { store.delete(column); try? context.save() }
                        .disabled(columns.count <= 1)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 22)
            }
```

- [ ] **Step 3: 编译确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat: board cards open edit popover; column header + opens create popover"
```

---

## Task 6: 手动验收（实跑）

SwiftUI 视图无法单测，按 spec 验收标准实跑 app 确认。

**Files:**（无改动；如发现缺陷回到对应 Task 修复）

- [ ] **Step 1: 启动 app**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -5`，构建产物后用 `open` 启动 `.app`（或在 Xcode 里 ⌘R）。

- [ ] **Step 2: 逐条核对验收标准**

对照 `docs/superpowers/specs/2026-05-30-unified-task-editor-popover-design.md` 的 10 条验收标准逐条点检，重点：

  1. 点列表/看板未完成卡片主体 → 弹编辑 popover，字段显示当前值。
  2. 改字段 → 关闭再开，值保留。
  3. 改截止时间 → 通知按新时间调度（旧的取消）。
  4. 编辑改状态 → 任务出现在对应看板列。
  5. 列表 `+` → 创建 popover（默认无状态）；看板列 `+` → 创建 popover（预选该列）。
  6. 创建填标题后 ⌘↩/保存 → 出现在所选状态；esc → 不创建。
  7. 创建标题为空时保存无效果。
  8. **看板卡片点击弹 popover 与拖拽移动列互不干扰**（重点风险项：确认单击=编辑、拖动=移动，不互相误触）。
  9. 点卡片完成圆圈 / `⋯` 菜单不弹编辑 popover。
  10. `CaptureView` 与看板列底 `+ 添加任务` 行为不变。

- [ ] **Step 3: 记录结果**

全部通过则在 PR/对话里说明；任一不通过，定位到对应 Task 修复后重跑本 Task。第 8 条若点击与拖拽冲突，调整 `TaskEditPopover` 的手势（如改用 `simultaneousGesture` 或仅在卡片特定区域响应点击），再回归。

---

## 自检

**Spec 覆盖：** 状态=看板列(Task 1)、共用表单(Task 2/3)、编辑实时保存(Task 3 EditEditor)、创建草稿+⌘↩(Task 3 CreateEditor)、列表接入(Task 4)、看板接入(Task 5)、CaptureView/AddTaskField 不动(未改动相关代码)、提醒重排(EditEditor.onDisappear / CreateEditor.save)、点击vs拖拽风险(Task 6 第8条) —— 均有对应任务。

**占位符：** 无 TBD/TODO；每个代码步骤含完整代码。

**类型一致性：** `setColumn(_:to:)`、`taskEditPopover(_:)`、`CreateTaskButton(columnID:)`、`TaskEditorView.Mode.edit/.create(columnID:)`、`TaskFormFields(...)` 的签名在定义处(Task 1-3)与调用处(Task 3-5)一致。
