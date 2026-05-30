# 统一看板与 TODO 弹窗 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 抽取共享样式层与共享任务卡片组件,统一看板、TODO 弹窗、Capture 三处面板的卡片外观、语义颜色与毛玻璃质感。

**Architecture:** 新增 `Theme`(唯一颜色/文案/尺寸来源)与 `TaskCardView`(纯展示卡片,行为由调用方注入);三个视图删除各自重复的颜色/文案私有方法改调 `Theme`,列表与看板共用 `TaskCardView`;Capture 外壳改为无边框毛玻璃,TODO 弹窗(MenuBarExtra)让系统毛玻璃透出。不改数据模型、Store、拖拽逻辑。

**Tech Stack:** SwiftUI · SwiftData · AppKit(NSPanel)· Swift Testing · Xcode 16 文件系统同步分组(新文件放入目录即自动入 target,无需改 pbxproj)

**Build/Test 命令:**
- 编译:`xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
- 全部测试:`xcodebuild test -scheme WorkPanel -destination 'platform=macOS'`
- 单个测试类:`xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ThemeTests`

> 现状参考:`priorityColor` 在 `TaskListView.swift:183`、`BoardView.swift:237`、`CaptureView.swift:104` 各有一份;`recurrenceLabel` 在 `TaskListView.swift:186`、`CaptureView.swift:107` 各有一份;`priorityLabel` 在 `CaptureView.swift:101`。本计划将其收敛到 `Theme`。

---

## Task 1: 新增 `Theme` 共享样式层(TDD)

**Files:**
- Create: `WorkPanel/UI/Theme.swift`
- Test: `WorkPanelTests/ThemeTests.swift`

- [ ] **Step 1: 写失败测试**

Create `WorkPanelTests/ThemeTests.swift`:

```swift
import Testing
import SwiftUI
@testable import WorkPanel

struct ThemeTests {
    @Test func priorityLabels() {
        #expect(Theme.priorityLabel(.high) == "高")
        #expect(Theme.priorityLabel(.medium) == "中")
        #expect(Theme.priorityLabel(.low) == "低")
    }

    @Test func recurrenceLabels() {
        #expect(Theme.recurrenceLabel(.daily) == "每天")
        #expect(Theme.recurrenceLabel(.weekdays) == "工作日")
        #expect(Theme.recurrenceLabel(.weekly) == "每周")
        #expect(Theme.recurrenceLabel(.monthly) == "每月")
    }

    @Test func priorityColors() {
        #expect(Theme.priority(.high) == .red)
        #expect(Theme.priority(.medium) == .orange)
        #expect(Theme.priority(.low) == .gray)
    }
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ThemeTests`
Expected: 编译失败 —— "cannot find 'Theme' in scope"。

- [ ] **Step 3: 实现 `Theme`**

Create `WorkPanel/UI/Theme.swift`:

```swift
import SwiftUI

/// 全 App 唯一的语义颜色、文案与尺寸来源。
/// 三处面板(列表 / 看板 / Capture)统一调用,避免重复实现导致的样式漂移。
enum Theme {
    // MARK: 语义色
    static func priority(_ p: Priority) -> Color {
        switch p { case .high: .red; case .medium: .orange; case .low: .gray }
    }
    static let tag: Color = .green
    static let deadline: Color = .blue
    static let recurrence: Color = .purple

    // MARK: 文案
    static func priorityLabel(_ p: Priority) -> String {
        switch p { case .high: "高"; case .medium: "中"; case .low: "低" }
    }
    static func recurrenceLabel(_ r: RecurrenceRule) -> String {
        switch r { case .daily: "每天"; case .weekdays: "工作日"; case .weekly: "每周"; case .monthly: "每月" }
    }

    // MARK: 尺寸 token
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 14
    static let titleFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let priorityDotSize: CGFloat = 7
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ThemeTests`
Expected: PASS（3 个测试全绿）。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/Theme.swift WorkPanelTests/ThemeTests.swift
git commit -m "feat: add Theme shared style tokens (colors/labels/sizes)"
```

---

## Task 2: 新增共享 `TaskCardView`

**Files:**
- Create: `WorkPanel/UI/TaskCardView.swift`

无视图测试设施,验证方式为编译通过(下游 Task 3/4 接入后才在 App 内可见)。

- [ ] **Step 1: 实现 `TaskCardView`**

Create `WorkPanel/UI/TaskCardView.swift`:

```swift
import SwiftUI

/// 看板与 TODO 列表共用的任务卡片。仅负责外观;
/// 菜单 / 拖拽 / contextMenu 等行为由调用方在 `trailing` 槽或外层修饰符注入。
struct TaskCardView<Trailing: View>: View {
    let task: TodoTask
    let onComplete: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onComplete) { Image(systemName: "circle") }
                .buttonStyle(.borderless)

            Circle()
                .fill(Theme.priority(task.priority))
                .frame(width: Theme.priorityDotSize, height: Theme.priorityDotSize)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: Theme.titleFontSize))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let d = task.deadline {
                        Text(d.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(d < .now ? .red : Theme.deadline)
                    }
                    if task.recurrence != nil {
                        Image(systemName: "repeat").foregroundStyle(Theme.recurrence)
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text("#\(tag)").foregroundStyle(Theme.tag)
                    }
                }
                .font(.system(size: Theme.metaFontSize))
            }

            Spacer(minLength: 0)
            trailing()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}
```

- [ ] **Step 2: 编译确认**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED（`TaskCardView` 暂未被引用,但泛型视图可独立编译）。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/TaskCardView.swift
git commit -m "feat: add shared TaskCardView (presentation-only task card)"
```

---

## Task 3: `TaskListView` 接入 Theme + TaskCardView + 毛玻璃透出

**Files:**
- Modify: `WorkPanel/UI/TaskListView.swift`

- [ ] **Step 1: `taskList` 让系统毛玻璃透出,卡片化行**

将 `taskList`(原 `TaskListView.swift:76-86`)替换为:

```swift
    private var taskList: some View {
        List(visibleTasks) { task in
            row(task)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if visibleTasks.isEmpty {
                ContentUnavailableView("没有任务", systemImage: "checkmark.circle")
            }
        }
    }
```

- [ ] **Step 2: `row` 改用 `TaskCardView`**

将 `row(_:)`(原 `TaskListView.swift:101-149`)整体替换为:

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

- [ ] **Step 3: 头部内边距对齐看板**

将 `header` 末尾(原 `TaskListView.swift:73`)的 `.padding(10)` 替换为:

```swift
        .padding(.horizontal, 14).padding(.vertical, 10)
```

- [ ] **Step 4: 删除孤儿私有方法**

删除文件末尾的 `priorityColor(_:)` 与 `recurrenceLabel(_:)`(原 `TaskListView.swift:183-188`)—— 它们已被 `TaskCardView` 内部的 `Theme.*` 取代,且 `row` 不再引用。

> 注意:`complete`、`snooze` 两个方法仍被 `row` 引用,**保留**。

- [ ] **Step 5: 编译确认**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED，无 "unused" 警告残留 `priorityColor`/`recurrenceLabel`。

- [ ] **Step 6: 提交**

```bash
git add WorkPanel/UI/TaskListView.swift
git commit -m "refactor: TaskListView uses TaskCardView + Theme, frosted list"
```

---

## Task 4: `BoardView` 接入 Theme + TaskCardView

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift`

- [ ] **Step 1: `card` 改用 `TaskCardView`**

将 `card(_:)`(原 `BoardView.swift:181-209`)整体替换为:

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

- [ ] **Step 2: 删除孤儿私有方法**

删除文件末尾的 `priorityColor(_:)`(原 `BoardView.swift:237-239`)—— 已被 `TaskCardView` 内的 `Theme.priority` 取代,`card` 不再引用。

> 注意:`complete`、`handleDrop`、`handleArchiveDrop`、`activeTasks` 等仍被引用,**保留**。归档列的迷你 cell(`archiveColumnView`,原 `BoardView.swift:148-158`)语义不同,**不改**。

- [ ] **Step 3: 编译确认**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "refactor: BoardView card uses shared TaskCardView + Theme"
```

---

## Task 5: `CaptureView` 接入 Theme + 毛玻璃外壳

**Files:**
- Modify: `WorkPanel/UI/CaptureView.swift`

- [ ] **Step 1: chips 改用 Theme 颜色**

将 `chips`(原 `CaptureView.swift:55-73`)中的颜色字面量替换为 `Theme.*`。替换后的 `chips`:

```swift
    @ViewBuilder private var chips: some View {
        HStack(spacing: 8) {
            if !parsed.title.isEmpty {
                chip(text: parsed.title, system: "text.alignleft", tint: .secondary)
            }
            if let deadline = parsed.deadline {
                chip(text: deadline.formatted(date: .abbreviated, time: .shortened),
                     system: "calendar", tint: Theme.deadline)
            }
            chip(text: Theme.priorityLabel(parsed.priority), system: "flag.fill", tint: Theme.priority(parsed.priority))
            ForEach(parsed.tags, id: \.self) { tag in
                chip(text: tag, system: "number", tint: Theme.tag)
            }
            if let rule = parsed.recurrence {
                chip(text: Theme.recurrenceLabel(rule), system: "repeat", tint: Theme.recurrence)
            }
        }
        .font(.system(size: 12))
    }
```

- [ ] **Step 2: 根视图加毛玻璃 + 圆角**

在 body 根 `VStack` 的 `.frame(width: 560)`(原 `CaptureView.swift:46`)之后,紧接着 `.onAppear` 之前,插入:

```swift
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
```

即顺序为:`.padding(18)` → `.frame(width: 560)` → `.background(.ultraThinMaterial)` → `.clipShape(...)` → `.onAppear { ... }`。

- [ ] **Step 3: 删除孤儿私有方法**

删除文件末尾的 `priorityLabel(_:)`、`priorityColor(_:)`、`recurrenceLabel(_:)`(原 `CaptureView.swift:101-109`)—— 全部由 `Theme.*` 取代,`chips` 不再引用。

- [ ] **Step 4: 编译确认**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/CaptureView.swift
git commit -m "refactor: CaptureView uses Theme colors + frosted material shell"
```

---

## Task 6: `PanelController` 改为无边框毛玻璃面板

**Files:**
- Modify: `WorkPanel/UI/PanelController.swift`

> `KeyablePanel`(`canBecomeKey == true`)已定义于 `BoardPanelController.swift`,同 module 可直接使用。

- [ ] **Step 1: 重写 `makePanel`**

将 `makePanel()`(原 `PanelController.swift:27-46`)整体替换为:

```swift
    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }
```

> 变更说明:`NSPanel(` → `KeyablePanel(`;styleMask 去掉 `.titled`/`.fullSizeContentView` 改 `.borderless`;新增 `isOpaque=false`/`backgroundColor=.clear`/`hasShadow=true`;删除 `titleVisibility`/`titlebarAppearsTransparent`/三行 `standardWindowButton`。保留 `delegate = self`(失焦自动消失)与 `isMovableByWindowBackground`。

- [ ] **Step 2: 编译确认**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 全量测试**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS'`
Expected: 全部测试 PASS（`ThemeTests`/`BoardStoreTests`/`TodoStoreTests`/`InputParserTests`/`ReminderSchedulerTests`/`TodoTaskTests`)。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/PanelController.swift
git commit -m "refactor: PanelController borderless frosted panel via KeyablePanel"
```

---

## Task 7: 手动验证(运行 App)

**Files:** 无改动 —— 验收。

- [ ] **Step 1: 启动 App**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build` 后在 Xcode 运行,或运行产物。

- [ ] **Step 2: 逐项核对**

- [ ] TODO 弹窗(点菜单栏图标):卡片浮在系统毛玻璃上,无不透明 List 底色;行间为卡片样式。
- [ ] Capture(⌘⌥ 捕获热键):无标题栏、毛玻璃 + 圆角;Esc 取消、⌘↩ 保存、失焦自动消失正常。
- [ ] 看板(⌘⌥K):卡片外观与 TODO 列表一致;拖拽、完成、删除、归档功能不变。
- [ ] 颜色一致:Capture 标签 chip 绿色、列表/卡片 `#标签` 绿色、截止时间蓝色、过期红色、重复紫色。

- [ ] **Step 3: 收尾提交(若手动验证期间有微调)**

```bash
git add -A && git commit -m "chore: manual verification tweaks for unified UI"
```

---

## Self-Review 结论

- **Spec 覆盖**:Part 1 → Task 1;Part 2 → Task 2 + 接入 Task 3/4;Part 3a(TODO 毛玻璃透出)→ Task 3 Step 1;Part 3b(Capture 外壳)→ Task 5 Step 2 + Task 6;Part 3c(看板不动)→ 无需任务;颜色统一(标签绿)→ Task 5 Step 1 + `TaskCardView` 内 `Theme.tag`;去重 → Task 3/4/5 各自删孤儿方法 + 验证项 7。
- **类型一致**:`Theme.priority`/`Theme.tag`/`Theme.deadline`/`Theme.recurrence`/`Theme.priorityLabel`/`Theme.recurrenceLabel`/`Theme.cardRadius`/`Theme.panelRadius`/`Theme.titleFontSize`/`Theme.metaFontSize`/`Theme.priorityDotSize` 在 Task 1 定义,后续任务引用名称一致;`TaskCardView(task:onComplete:trailing:)` 签名在 Task 2 定义,Task 3 传 `Menu`、Task 4 传 `EmptyView()` 一致;`KeyablePanel` 来自 `BoardPanelController.swift`。
- **无占位符**:每个改代码的 Step 均给出完整代码或精确删除/插入位置。
