# 任务编辑器改走捕获面板 实现计划（修订 v2）

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** 把创建/编辑统一编辑器从"贴卡片 popover"改为"捕获面板（居中浮窗）"呈现；点卡片打开编辑、`⌘⌥J`/`+` 打开创建；显式 `⌘↩` 保存。

**Architecture:** 复用 `BoardStore.setColumn` 与 `TaskFormFields`。重写 `TaskEditorView` 为面板承载、本地 `@State`、显式保存、`onClose` 关闭的统一视图（创建/编辑由 `Mode` 决定 seeding 与保存动作）。卡片通过 `Notification.Name.openTaskEditor`（object 携带 `TaskEditorView.Mode`）通知 `AppDelegate`，由其在捕获面板 `PanelController` 中呈现。删除 popover 接线与被取代的 `CaptureView`。看板卡片加顶部拖动条分离点击/拖拽。

**Tech Stack:** SwiftUI + SwiftData，Swift Testing。Xcode 16 同步文件组（删除 .swift 用 `git rm`；新增放 `WorkPanel/UI/` 自动进 target）。

**构建命令：** `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -20`
**测试命令：** `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests 2>&1 | tail -20`

> **执行说明（重要）：** 这是一次紧耦合重构——删除旧符号(`TaskEditPopover`/`CreateTaskButton`/`CaptureView`)与更新所有调用方必须同时发生，否则中间状态无法编译。因此 **Task R1 是原子任务**：一次性完成全部 5 处文件改动，最后构建一次（应为绿），单次提交。不要分文件分别构建/提交。

---

## 文件结构

| 文件 | 动作 |
|---|---|
| `WorkPanel/UI/TaskEditorView.swift` | 重写为面板编辑器 + `Mode` + `Notification.Name.openTaskEditor`；删 `TaskEditPopover`/`CreateTaskButton` |
| `WorkPanel/WorkPanelApp.swift` | `AppDelegate`：`toggleCapture` 改开编辑器；加 `.openTaskEditor` 观察者；删 `CaptureView` 引用 |
| `WorkPanel/UI/CaptureView.swift` | `git rm` 删除 |
| `WorkPanel/UI/TaskListView.swift` | 撤 popover 接线；卡片点击发编辑通知；头部 `+` 发创建通知 |
| `WorkPanel/UI/BoardView.swift` | 撤 popover 接线；卡片顶部拖动条 + 主体点击发编辑通知；列头 `+` 发创建通知 |

---

## Task R1: 原子重构 — 编辑器改走捕获面板

按 1–5 全部改完后再构建、提交。

### 1. 覆盖 `WorkPanel/UI/TaskEditorView.swift`

先 `grep -rn "openSettings" WorkPanel --include="*.swift"` 看 `.openSettings` 定义在哪。若它在某文件的 `extension Notification.Name {}` 中，把 `openTaskEditor` 加到那里，并删除下方内容顶部的 `extension Notification.Name` 块（避免重复定义）。然后用以下内容整体覆盖该文件：

```swift
import SwiftUI
import SwiftData

extension Notification.Name {
    /// object 携带 `TaskEditorView.Mode`：请求在捕获面板中打开任务编辑器。
    static let openTaskEditor = Notification.Name("openTaskEditor")
}

/// 创建 / 编辑任务的统一编辑器。在捕获面板(PanelController)中居中呈现。
/// 本地 @State 草稿,显式 ⌘↩ 保存 / esc 取消;创建与编辑由 Mode 决定 seeding 与保存动作。
struct TaskEditorView: View {
    enum Mode {
        case create(columnID: UUID?)
        case edit(TodoTask)
    }

    let mode: Mode
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    private var todoStore: TodoStore { TodoStore(context: context) }
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    @State private var title: String
    @State private var notes: String
    @State private var deadline: Date?
    @State private var priority: Priority
    @State private var tags: [String]
    @State private var recurrence: RecurrenceRule?
    @State private var columnID: UUID?

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let columnID):
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _deadline = State(initialValue: nil)
            _priority = State(initialValue: AppSettings.defaultPriority)
            _tags = State(initialValue: [])
            _recurrence = State(initialValue: nil)
            _columnID = State(initialValue: columnID)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _notes = State(initialValue: task.notes)
            _deadline = State(initialValue: task.deadline)
            _priority = State(initialValue: task.priority)
            _tags = State(initialValue: task.tags)
            _recurrence = State(initialValue: task.recurrence)
            _columnID = State(initialValue: task.columnID)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "编辑任务" : "新建任务").font(.headline)

            TaskFormFields(
                title: $title, notes: $notes, deadline: $deadline,
                priority: $priority, tags: $tags, recurrence: $recurrence,
                columnID: $columnID, columns: columns)

            HStack {
                Spacer()
                Button("取消") { onClose() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { save(); return .handled }
            return .ignored
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let task: TodoTask
        switch mode {
        case .create:
            var parsed = ParsedInput()
            parsed.title = trimmed
            parsed.deadline = deadline
            parsed.priority = priority
            parsed.tags = tags
            parsed.recurrence = recurrence
            task = todoStore.add(parsed, notes: notes)
        case .edit(let existing):
            existing.title = trimmed
            existing.notes = notes
            existing.deadline = deadline
            existing.priority = priority
            existing.tags = tags
            existing.recurrence = recurrence
            task = existing
        }
        boardStore.setColumn(task, to: columnID)
        try? context.save()
        Task { await scheduler.schedule(for: task) }
        onClose()
    }
}
```

（注意：旧的 `TaskEditPopover` `ViewModifier`、`extension View { taskEditPopover }`、`CreateTaskButton` **不再保留**——上面整体覆盖即删除了它们。）

### 2. 改 `WorkPanel/WorkPanelApp.swift`（AppDelegate）

在 `applicationDidFinishLaunching` 的 `.openSettings` 观察者之后加入：

```swift
        NotificationCenter.default.addObserver(forName: .openTaskEditor, object: nil, queue: .main) { [weak self] note in
            guard let mode = note.object as? TaskEditorView.Mode else { return }
            MainActor.assumeIsolated { self?.showEditor(mode) }
        }
```

把整个 `toggleCapture()` 方法替换为：

```swift
    private func toggleCapture() {
        if panel.isVisible { panel.hide(); return }
        showEditor(.create(columnID: nil))
    }

    private func showEditor(_ mode: TaskEditorView.Mode) {
        panel.show {
            TaskEditorView(mode: mode, onClose: { [weak self] in self?.panel.hide() })
                .modelContainer(SharedModel.container)
        }
    }
```

删除原 `toggleCapture` 内手建的 `ModelContext` / `TodoStore` / `CaptureView(...)` 等（保存逻辑已在 `TaskEditorView.save()`）。

### 3. 删除 CaptureView

```bash
git rm WorkPanel/UI/CaptureView.swift
```

### 4. 改 `WorkPanel/UI/TaskListView.swift`

`row(_:)` 结尾把上一轮的 `.taskEditPopover(task)` 改为点击发通知：

```swift
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .openTaskEditor, object: TaskEditorView.Mode.edit(task))
        }
    }
```

`header` 把上一轮的 `CreateTaskButton(columnID: nil)` 改为按钮发通知：

```swift
            .menuStyle(.borderlessButton)
            .frame(width: 28)

            Button {
                NotificationCenter.default.post(name: .openTaskEditor, object: TaskEditorView.Mode.create(columnID: nil))
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .frame(width: 28)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
```

### 5. 改 `WorkPanel/UI/BoardView.swift`

把 `card(_:)` 替换为（顶部拖动条 `.draggable`；主体点击发编辑通知；右键删除保留；外层补同色圆角背景让拖动条融入卡片）：

```swift
    private func card(_ task: TodoTask) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .draggable(task.id.uuidString)

            TaskCardView(task: task, onComplete: { complete(task) }) { EmptyView() }
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .openTaskEditor, object: TaskEditorView.Mode.edit(task))
                }
        }
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .contextMenu {
            Button("删除", role: .destructive) {
                scheduler.cancel(for: task); context.delete(task); try? context.save()
            }
        }
    }
```

列头把上一轮的 `CreateTaskButton(columnID: column.id)` 改为按钮发通知：

```swift
                Button {
                    NotificationCenter.default.post(name: .openTaskEditor, object: TaskEditorView.Mode.create(columnID: column.id))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 22)
```

### 6. 构建（全工程，一次）

Run 构建命令。Expected: `BUILD SUCCEEDED`，无对 `taskEditPopover`/`CreateTaskButton`/`CaptureView` 的残留引用。若报这些符号未找到，说明某调用方没改干净——回到对应文件修。

### 7. 提交（单次）

```bash
git add -A
git commit -m "refactor: route create/edit through capture panel; drop popover + CaptureView"
```

---

## Task R2: 全量测试 + 手动验收

- [ ] **Step 1: 全量测试** — Run 测试命令。Expected: `WorkPanelTests` 全过（`testLaunchPerformance` UI 性能测试与本功能无关，忽略）。
- [ ] **Step 2: 手动验收（实跑 app）**，按 spec 修订 v2 验收 1–8：
  - `⌘⌥J` 开空白创建编辑器；再按关闭。
  - 点列表/看板卡片主体 → 捕获面板预填该任务字段；`⌘↩` 保存、`esc` 丢弃。
  - 列表头 `+` / 看板列头 `+` → 创建（看板预选该列）。
  - 看板卡片：拖**顶部条**=移动列；点**主体**=编辑；点完成圆圈=完成；互不误触。
  - 看板列底 `+ 添加任务` 不变。
- [ ] **Step 3: 记录结果**；任一不过定位修复。

---

## 自检
- 复用：`BoardStore.setColumn`、`TaskFormFields` 未改。
- 移除：`TaskEditPopover`/`CreateTaskButton`(整体覆盖删除)、`CaptureView`(git rm)。
- 跨上下文：编辑器用 `SharedModel.container` 主上下文，`.edit(task)` 同对象有效。
- 类型一致：`TaskEditorView.Mode.create(columnID:)`/`.edit(_:)`、`.openTaskEditor`、`showEditor(_:)` 定义与使用一致。
- 点击/拖拽：分到不同子视图（主体 vs 顶部条），不竞争。
