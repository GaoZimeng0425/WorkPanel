# 捕获面板显式控件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给捕获/编辑面板（`TaskEditorView`）加三个显式控件——重要程度、状态（看板列）、标签多选——让控件成为 priority/tags/columnID 的唯一来源。

**Architecture:** 解析器与 `CaptureDraft.resolve` 不动；在保存路径上用一个纯函数 `CaptureDraft.applyControls` 把控件的 priority/tags 覆盖到解析结果之上；`columnID` 经现有 `BoardStore.setColumn` 写入。标签多选拆成独立的 `TagPickerField`（popover：顶部输入框同时筛选+新建）。重要程度复用 `NoirSegmented`，状态用原生 `Menu`。

**Tech Stack:** SwiftUI · SwiftData（`@Query` / `ModelContext`）· Swift Testing（`import Testing`, `@Test`, `#expect`）· xcodebuild（scheme `WorkPanel`）。

参考 spec：`docs/superpowers/specs/2026-05-31-capture-explicit-controls-design.md`

---

## 文件结构

- **Modify** `WorkPanel/Parsing/CaptureDraft.swift` — 新增纯函数 `applyControls(to:priority:tags:)`。
- **Modify** `WorkPanel/UI/TaskEditorView.swift` — 新增三个 `@State` + `@Query`；`init` 播种；控件行 UI；`save()` 用 `applyControls`；`TokenStrip` 收窄；提示文案更新。
- **Create** `WorkPanel/UI/TagPickerField.swift` — 标签 popover 多选控件，含 `static func summary(_:)`。
- **Modify** `WorkPanelTests/CaptureDraftTests.swift` — 新增 `applyControls` 断言。
- **Create** `WorkPanelTests/TagPickerFieldTests.swift` — 测 `summary` 折叠规则。

测试命令一律按套件 `-only-testing`（避免全量 `xcodebuild test` 卡住 testmanagerd，见记忆 `xcodebuild-test-daemon-hang`）。

---

## Task 1: `CaptureDraft.applyControls` — 控件覆盖解析结果（纯函数）

**Files:**
- Modify: `WorkPanel/Parsing/CaptureDraft.swift`
- Test: `WorkPanelTests/CaptureDraftTests.swift`

- [ ] **Step 1: Write the failing tests**

在 `WorkPanelTests/CaptureDraftTests.swift` 的 `emptyTextYieldsEmptyTitleAndNotes` 测试之后、闭合大括号之前，追加：

```swift
    @Test func applyControlsOverridesPriorityAndTags() {
        var fields = ParsedInput()
        fields.priority = .low                 // 解析自 token 的值
        fields.tags = ["解析来的"]
        let out = CaptureDraft.applyControls(to: fields, priority: .high, tags: ["工作"])
        #expect(out.priority == .high)         // 控件为准
        #expect(out.tags == ["工作"])          // 控件为准
    }

    @Test func applyControlsKeepsDeadlineRecurrenceUrgency() {
        var fields = ParsedInput()
        fields.deadline = now
        fields.recurrence = .weekly
        fields.urgencyOverride = true
        let out = CaptureDraft.applyControls(to: fields, priority: .medium, tags: [])
        #expect(out.deadline == now)           // 仍来自 token
        #expect(out.recurrence == .weekly)
        #expect(out.urgencyOverride == true)
        #expect(out.tags == [])                // 控件清空标签
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/CaptureDraftTests 2>&1 | tail -15
```
Expected: 编译失败，`type 'CaptureDraft' has no member 'applyControls'`。

- [ ] **Step 3: Implement the function**

在 `WorkPanel/Parsing/CaptureDraft.swift` 的 `resolve(...)` 方法之后、`enum CaptureDraft` 闭合括号之前，加入：

```swift
    /// 控件为 priority/tags 的唯一来源:用捕获面板控件值覆盖解析结果。
    /// deadline/recurrence/urgencyOverride 仍来自第一行 token,原样保留。
    nonisolated static func applyControls(to fields: ParsedInput,
                                          priority: Priority,
                                          tags: [String]) -> ParsedInput {
        var out = fields
        out.priority = priority
        out.tags = tags
        return out
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/CaptureDraftTests 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **`，CaptureDraftTests 全绿（含既有 token 解析测试）。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Parsing/CaptureDraft.swift WorkPanelTests/CaptureDraftTests.swift
git commit -m "feat(capture): applyControls — 控件覆盖解析出的 priority/tags"
```

---

## Task 2: `TagPickerField` 标签多选控件 + 摘要规则

**Files:**
- Create: `WorkPanel/UI/TagPickerField.swift`
- Test: `WorkPanelTests/TagPickerFieldTests.swift`

- [ ] **Step 1: Write the failing tests**

新建 `WorkPanelTests/TagPickerFieldTests.swift`：

```swift
import Testing
@testable import WorkPanel

struct TagPickerFieldTests {
    @Test func summaryEmptyIsPlaceholder() {
        #expect(TagPickerField.summary([]) == "标签")
    }
    @Test func summaryUpToThreeJoinsNames() {
        #expect(TagPickerField.summary(["工作"]) == "工作")
        #expect(TagPickerField.summary(["工作", "学习"]) == "工作 学习")
        #expect(TagPickerField.summary(["工作", "学习", "紧急"]) == "工作 学习 紧急")
    }
    @Test func summaryOverThreeCollapses() {
        #expect(TagPickerField.summary(["工作", "学习", "紧急", "家庭"]) == "工作 等4个标签")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/TagPickerFieldTests 2>&1 | tail -15
```
Expected: 编译失败，`cannot find 'TagPickerField' in scope`。

- [ ] **Step 3: Create the component**

新建 `WorkPanel/UI/TagPickerField.swift`：

```swift
import SwiftUI

/// 捕获面板的标签多选控件(GitHub Labels / Notion 多选属性 风格):
/// 收起态 pill 显示摘要;点开 popover,顶部输入框同时筛选已有标签与新建。
struct TagPickerField: View {
    @Binding var selected: [String]
    let existing: [String]          // 已有标签全集(去重排序)

    @State private var showing = false
    @State private var filter = ""

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 4) {
                Text(Self.summary(selected))
                    .foregroundStyle(selected.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Theme.surfaceEmphasis))
            .overlay(Capsule(style: .continuous).stroke(Theme.stroke, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) { popover }
    }

    private var trimmed: String { filter.trimmingCharacters(in: .whitespaces) }
    private var matches: [String] {
        guard !trimmed.isEmpty else { return existing }
        return existing.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
    private var canCreate: Bool { !trimmed.isEmpty && !existing.contains(trimmed) }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("筛选或新建标签", text: $filter)
                .textFieldStyle(.plain)
                .padding(8)
                .onSubmit { if canCreate { create() } }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if canCreate {
                        row(title: "新建『\(trimmed)』", checked: false) { create() }
                    }
                    ForEach(matches, id: \.self) { tag in
                        row(title: "#\(tag)", checked: selected.contains(tag)) { toggle(tag) }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 220)
        .background(Theme.panelBottom)
        .preferredColorScheme(.dark)
    }

    private func row(title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer()
                if checked { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ tag: String) {
        if let i = selected.firstIndex(of: tag) { selected.remove(at: i) }
        else { selected.append(tag) }
    }
    private func create() {
        guard !trimmed.isEmpty, !selected.contains(trimmed) else { return }
        selected.append(trimmed)
        filter = ""
    }

    /// 收起态摘要:0→占位「标签」;1–3→空格连名;>3→「首个 等N个标签」。
    static func summary(_ tags: [String]) -> String {
        switch tags.count {
        case 0: return "标签"
        case 1...3: return tags.joined(separator: " ")
        default: return "\(tags[0]) 等\(tags.count)个标签"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/TagPickerFieldTests 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **`，3 个 summary 测试全绿。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/TagPickerField.swift WorkPanelTests/TagPickerFieldTests.swift
git commit -m "feat(capture): TagPickerField — popover 标签多选(筛选+新建)"
```

---

## Task 3: 把三个控件接入 `TaskEditorView`

**Files:**
- Modify: `WorkPanel/UI/TaskEditorView.swift`

本任务是 UI 接线（无新单测；逻辑已在 Task 1/2 用 TDD 覆盖）。验证 = 编译通过 + 既有测试全绿 + 手动冒烟。

- [ ] **Step 1: 替换 `@State`/属性声明与 `init`（播种控件初值）**

把 `WorkPanel/UI/TaskEditorView.swift` 中现有的这段：

```swift
    @State private var text: String
    @State private var previewing = false
    private let base: ParsedInput
    private let columnID: UUID?

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let columnID):
            _text = State(initialValue: "")
            var b = ParsedInput()
            b.priority = AppSettings.defaultPriority
            base = b
            self.columnID = columnID
        case .edit(let task):
            _text = State(initialValue: task.notes.isEmpty ? task.title : task.title + "\n" + task.notes)
            var b = ParsedInput()
            b.deadline = task.deadline
            b.priority = task.priority
            b.tags = task.tags
            b.recurrence = task.recurrence
            b.urgencyOverride = task.urgencyOverride
            base = b
            self.columnID = task.columnID
        }
    }
```

整体替换为（新增 `@State` 三件套 + `@Query`，`columnID` 由 `let` 改 `@State`）：

```swift
    @State private var text: String
    @State private var previewing = false
    @State private var priority: Priority
    @State private var selectedTags: [String]
    @State private var columnID: UUID?
    private let base: ParsedInput

    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    @Query private var allTasks: [TodoTask]

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let columnID):
            _text = State(initialValue: "")
            var b = ParsedInput()
            b.priority = AppSettings.defaultPriority
            base = b
            _priority = State(initialValue: AppSettings.defaultPriority)
            _selectedTags = State(initialValue: [])
            _columnID = State(initialValue: columnID)
        case .edit(let task):
            _text = State(initialValue: task.notes.isEmpty ? task.title : task.title + "\n" + task.notes)
            var b = ParsedInput()
            b.deadline = task.deadline
            b.priority = task.priority
            b.tags = task.tags
            b.recurrence = task.recurrence
            b.urgencyOverride = task.urgencyOverride
            base = b
            _priority = State(initialValue: task.priority)
            _selectedTags = State(initialValue: task.tags)
            _columnID = State(initialValue: task.columnID)
        }
    }

    private var allTags: [String] {
        Array(Set(allTasks.flatMap(\.tags))).sorted()
    }
```

- [ ] **Step 2: 在 body 里插入控件区**

在 `body` 中，找到编辑器 `Group { ... }.frame(height: 220).overlay(...)` 这一块，在它**之后**、`HStack {` （footer 取消/保存那行）**之前**，插入：

```swift
            controls
```

并在 `save()` 方法**之前**新增以下私有视图与辅助：

```swift
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlRow("重要程度") {
                NoirSegmented(
                    segments: Priority.allCases.map {
                        .init(value: $0, label: Theme.priorityLabel($0))
                    },
                    selection: $priority
                )
            }
            controlRow("状态") { statusMenu }
            controlRow("标签") {
                TagPickerField(selected: $selectedTags, existing: allTags)
            }
        }
    }

    private func controlRow<C: View>(_ label: String,
                                     @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .frame(width: 56, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var currentColumnName: String {
        guard let id = columnID else { return "无" }
        return columns.first { $0.id == id }?.name ?? "无"
    }

    private var statusMenu: some View {
        Menu {
            Button { columnID = nil } label: {
                if columnID == nil { Label("无", systemImage: "checkmark") } else { Text("无") }
            }
            ForEach(columns) { col in
                Button { columnID = col.id } label: {
                    if columnID == col.id { Label(col.name, systemImage: "checkmark") }
                    else { Text(col.name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentColumnName)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Theme.surfaceEmphasis))
            .overlay(Capsule(style: .continuous).stroke(Theme.stroke, lineWidth: 0.6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
```

- [ ] **Step 3: 改 `save()` 用 `applyControls` + 控件值**

把 `save()` 里这两行：

```swift
        var fields = r.fields
        fields.title = title
```

替换为：

```swift
        var fields = CaptureDraft.applyControls(to: r.fields,
                                                priority: priority,
                                                tags: selectedTags)
        fields.title = title
```

`save()` 末尾的 `boardStore.setColumn(task, to: columnID)` 保持不变（`columnID` 现在是 `@State`，语义一致）。

- [ ] **Step 4: 收窄 `TokenStrip`，更新提示文案**

在 `private struct TokenStrip` 中，把 `chipTexts` 整体替换为（去掉 priority 与 tags，只留 token 派生项）：

```swift
    private var chipTexts: [String] {
        var out: [String] = []
        if let u = fields.urgencyOverride {
            out.append(u ? "紧急" : "不紧急")
        }
        if let d = fields.deadline {
            out.append(d.formatted(date: .abbreviated, time: .shortened))
        }
        if let r = fields.recurrence {
            out.append(Theme.recurrenceLabel(r))
        }
        return out
    }
```

并把 `TokenStrip.body` 里的占位提示判断与文案：

```swift
            if chips.count <= 1 {
                Text("可在第一行用如「明天 !高 #工作」补充")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
```

替换为：

```swift
            if chips.isEmpty {
                Text("可在第一行用如「明天 18:00 每周一」补充")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
```

- [ ] **Step 5: 编译并跑既有相关套件**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`。

再跑解析相关套件确认无回归：
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/CaptureDraftTests \
  -only-testing:WorkPanelTests/InputParserTests 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: 手动冒烟（运行 App）**

启动 App，⌘ 触发捕获面板，确认：
1. 三个控件出现在文本域下方：重要程度（低/中/高分段）、状态（Menu，含库内看板列 + 无）、标签（pill）。
2. 标签 pill 点开 popover：输入框可筛选已有标签；输入新词出现「新建『…』」，回车后被选中；收起态 >3 个显示「首个 等N个标签」。
3. 设重要程度=高、状态=某列、选 1 个标签，保存后该任务在看板对应列、卡片显示高优先级点与该标签。
4. 编辑已有任务时三个控件回显当前值；第一行写 `明天 18:00` 仍能设置截止。

- [ ] **Step 7: Commit**

```bash
git add WorkPanel/UI/TaskEditorView.swift
git commit -m "feat(capture): 捕获面板接入重要程度/状态/标签三控件"
```

---

## Self-Review

**Spec 覆盖：**
- 控件为 priority/tags 唯一来源 → Task 1（`applyControls`）+ Task 3 Step 3。
- 重要程度（NoirSegmented 三段）→ Task 3 Step 2 `controls`。
- 状态（Menu，与看板共用 `BoardColumn`）→ Task 3 Step 2 `statusMenu` + `@Query columns`。
- 标签 popover 多选（筛选+新建，收起摘要规则）→ Task 2（`TagPickerField`/`summary`）。
- TokenStrip 收窄 + 提示改文案 → Task 3 Step 4。
- `InputParser`/`CaptureDraft.resolve` 不改 → 仅新增 `applyControls`，既有测试保留。
- 测试：`applyControls` 断言（Task 1）、`summary` 折叠（Task 2）、回归（Task 3 Step 5）。

**Placeholder 扫描：** 无 TBD/TODO；每个改代码的步骤均给出完整代码块。

**类型一致性：** `applyControls(to:priority:tags:)`、`TagPickerField(selected:existing:)`、`TagPickerField.summary(_:)`、`NoirSegmented<Priority>`、`Priority.allCases`/`Theme.priorityLabel`、`@Query(sort: \BoardColumn.order)`、`BoardStore.setColumn(_:to:)` 在各任务中签名一致。
