# 单文本域 · 行内实时渲染捕获编辑器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把任务捕获编辑器收敛为单个文本域(第一行=标题、其余=markdown 备注),编辑时行内即时套用 markdown 样式;看板「+ 添加任务」也走该捕获面板。

**Architecture:** 纯函数 `CaptureDraft.resolve` 负责「拆分第一行/正文 + 以既有值为基准合并解析结果(缺省即保留)」,可单测;`MarkdownTextEditor`(`NSViewRepresentable` 包裹 `NSTextView`)负责编辑时行内套样式(方案 A,标记可见),由 `MarkdownStyler` 用 TextKit 套属性;`TaskEditorView` 重写为「token 条 + 单编辑器」并经 `CaptureDraft` 保存;`BoardView` 底部「+ 添加任务」改为打开捕获面板。

**Tech Stack:** Swift, SwiftUI, SwiftData, AppKit/TextKit(`NSTextView`),swift-testing(`import Testing`)。Xcode 16 同步文件组(objectVersion 77)——新增 `.swift` 文件放入对应文件夹即自动加入 target,无需改 `project.pbxproj`。

**通用命令:**
- 测试:`xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -30`
- 编译:`xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -quiet 2>&1 | tail -30`

---

## 文件结构

- 新建 `WorkPanel/Parsing/CaptureDraft.swift` —— 纯函数:文本→(字段, 备注)。
- 新建 `WorkPanelTests/CaptureDraftTests.swift` —— `CaptureDraft.resolve` 单测。
- 新建 `WorkPanel/UI/MarkdownTextEditor.swift` —— `NSViewRepresentable` + `CaptureTextView` + `MarkdownStyler`。
- 改写 `WorkPanel/UI/TaskEditorView.swift` —— 单编辑器 + token 条 + 经 `CaptureDraft` 保存。
- 删除 `WorkPanel/UI/TaskFormFields.swift` —— 改写后成为孤儿。
- 修改 `WorkPanel/UI/BoardView.swift` —— 底部「+ 添加任务」改为打开面板;删除 `addTaskField(_:)` 与 `AddTaskField`。

---

## Task 1: `CaptureDraft` 纯函数 + 单测

**Files:**
- Create: `WorkPanel/Parsing/CaptureDraft.swift`
- Test: `WorkPanelTests/CaptureDraftTests.swift`

- [ ] **Step 1: 写失败测试**

Create `WorkPanelTests/CaptureDraftTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

struct CaptureDraftTests {
    // 固定基准:2026-06-01 10:00,Asia/Shanghai,Gregorian(与 InputParserTests 一致)。
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 0))!
    }
    private func resolve(_ text: String, base: ParsedInput = ParsedInput())
        -> (fields: ParsedInput, notes: String) {
        CaptureDraft.resolve(text: text, base: base, now: now, calendar: calendar)
    }

    @Test func firstLineIsTitleRestIsNotes() {
        let r = resolve("写周报\n## 要点\n- 收集数据")
        #expect(r.fields.title == "写周报")
        #expect(r.notes == "## 要点\n- 收集数据")
    }

    @Test func firstLineTokensParsed() {
        let r = resolve("写周报 明天 !高 #工作")
        #expect(r.fields.title == "写周报")
        #expect(r.fields.priority == .high)
        #expect(r.fields.tags == ["工作"])
        #expect(r.fields.deadline != nil)
    }

    @Test func absenceKeepsBaseValues() {
        var base = ParsedInput()
        base.deadline = now
        base.tags = ["旧"]
        base.priority = .high
        let r = resolve("改标题", base: base)        // 第一行无 token
        #expect(r.fields.title == "改标题")
        #expect(r.fields.deadline == now)            // 保留
        #expect(r.fields.tags == ["旧"])             // 保留
        #expect(r.fields.priority == .high)          // 保留(parse 以 base.priority 为默认)
    }

    @Test func firstLineTagsOverrideBase() {
        var base = ParsedInput()
        base.tags = ["旧"]
        let r = resolve("改标题 #新", base: base)
        #expect(r.fields.tags == ["新"])
    }

    @Test func emptyTextYieldsEmptyTitleAndNotes() {
        let r = resolve("")
        #expect(r.fields.title == "")
        #expect(r.notes == "")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/CaptureDraftTests 2>&1 | tail -30`
Expected: 编译失败 / FAIL —— `CaptureDraft` 未定义。

- [ ] **Step 3: 实现 `CaptureDraft`**

Create `WorkPanel/Parsing/CaptureDraft.swift`:

```swift
import Foundation

/// 把捕获编辑器整段文本拆成「第一行(标题 + token)」与「其余行(markdown 备注)」,
/// 并以 base 为基准合并解析结果(缺省即保留)。纯函数,便于测试。
enum CaptureDraft {
    static func resolve(text: String,
                        base: ParsedInput,
                        now: Date,
                        calendar: Calendar = .current) -> (fields: ParsedInput, notes: String) {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let firstLine = parts.first.map(String.init) ?? ""
        let body = parts.count > 1 ? String(parts[1]) : ""

        let parsed = InputParser(calendar: calendar)
            .parse(firstLine, now: now, defaultPriority: base.priority)

        var fields = ParsedInput()
        fields.title = parsed.title
        fields.priority = parsed.priority                                  // parse 以 base.priority 为默认
        fields.deadline = parsed.deadline ?? base.deadline                 // 缺省即保留
        fields.tags = parsed.tags.isEmpty ? base.tags : parsed.tags        // 缺省即保留
        fields.recurrence = parsed.recurrence ?? base.recurrence           // 缺省即保留
        return (fields, body)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/CaptureDraftTests 2>&1 | tail -30`
Expected: PASS(5 tests）。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/CaptureDraft.swift WorkPanelTests/CaptureDraftTests.swift
git commit -m "feat: CaptureDraft resolves first-line title + body notes with keep-on-absence merge"
```

---

## Task 2: `MarkdownTextEditor`(行内实时套样式)

**Files:**
- Create: `WorkPanel/UI/MarkdownTextEditor.swift`

无单测(AppKit 渲染),以编译 + 运行人工验证。

- [ ] **Step 1: 实现组件**

Create `WorkPanel/UI/MarkdownTextEditor.swift`:

```swift
import SwiftUI
import AppKit

/// 单文本域 markdown 编辑器:编辑时即时套用样式(标记保留可见,方案 A)。
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSave: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CaptureTextView()
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.onCancel = onCancel
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = MarkdownStyler.baseFont
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.autoresizingMask = [.width]
        textView.string = text
        if let storage = textView.textStorage { MarkdownStyler.apply(to: storage) }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? CaptureTextView else { return }
        textView.onSave = onSave
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
            if let storage = textView.textStorage { MarkdownStyler.apply(to: storage) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownTextEditor
        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            if let storage = tv.textStorage { MarkdownStyler.apply(to: storage) }
        }
    }
}

/// 普通 Return = 换行;⌘Return = 保存;esc = 取消。
final class CaptureTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) {  // 36 = Return
            onSave?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {  // esc
        onCancel?()
    }
}

/// 用 TextKit 给 NSTextStorage 套 markdown 样式(标记保留可见)。
enum MarkdownStyler {
    static let baseFont = NSFont.systemFont(ofSize: 13)

    static func apply(to storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let ns = storage.string as NSString

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: full)

        // 行级:第一行=标题样式;# 标题;> 引用
        ns.enumerateSubstrings(in: full, options: [.byLines]) { sub, lineRange, _, _ in
            let line = sub ?? ""
            if lineRange.location == 0 {
                storage.addAttribute(.font,
                    value: NSFont.systemFont(ofSize: baseFont.pointSize + 5, weight: .semibold),
                    range: lineRange)
            }
            if let level = headingLevel(line) {
                let size = baseFont.pointSize + CGFloat(max(1, 6 - level * 2))
                storage.addAttribute(.font,
                    value: NSFont.systemFont(ofSize: size, weight: .bold), range: lineRange)
            } else if line.hasPrefix("> ") {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
            }
        }

        // 行内:加粗、斜体(用 NSFontManager 叠加 trait,可与已有样式组合)、行内代码
        addTrait(.boldFontMask, pattern: "(\\*\\*|__)(.+?)\\1", to: storage)
        addTrait(.italicFontMask, pattern: "(?<![\\*_])([\\*_])([^\\*_]+)\\1(?![\\*_])", to: storage)
        styleCode("`([^`]+)`", to: storage)

        storage.endEditing()
    }

    private static func headingLevel(_ line: String) -> Int? {
        var n = 0
        for ch in line { if ch == "#" { n += 1 } else { break } }
        guard (1...3).contains(n) else { return nil }
        return line.dropFirst(n).first == " " ? n : nil
    }

    private static func addTrait(_ trait: NSFontTraitMask, pattern: String, to storage: NSTextStorage) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(location: 0, length: storage.length)
        let fm = NSFontManager.shared
        re.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let r = match?.range else { return }
            storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                let f = (value as? NSFont) ?? baseFont
                storage.addAttribute(.font, value: fm.convert(f, toHaveTrait: trait), range: sub)
            }
        }
    }

    private static func styleCode(_ pattern: String, to storage: NSTextStorage) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(location: 0, length: storage.length)
        re.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.font,
                value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular), range: r)
            storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: r)
        }
    }
}
```

- [ ] **Step 2: 编译确认通过**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -quiet 2>&1 | tail -30`
Expected: BUILD SUCCEEDED(此时组件尚未被引用,仅验证可编译)。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/MarkdownTextEditor.swift
git commit -m "feat: MarkdownTextEditor with live inline markdown styling (visible markers)"
```

---

## Task 3: 重写 `TaskEditorView`(单编辑器 + token 条);删除 `TaskFormFields`

**Files:**
- Modify(整体改写): `WorkPanel/UI/TaskEditorView.swift`
- Delete: `WorkPanel/UI/TaskFormFields.swift`

- [ ] **Step 1: 整体改写 `TaskEditorView.swift`**

Replace the whole file `WorkPanel/UI/TaskEditorView.swift` with:

```swift
import SwiftUI
import SwiftData

/// 创建 / 编辑任务的统一编辑器:单个 markdown 文本域,第一行为标题,其余为备注。
/// 第一行可用自然语言 token(如「明天 !高 #工作」)设置截止/优先级/标签/重复;
/// 编辑态缺省即保留(不通过删 token 清除)。⌘↩ 保存 / esc 取消。
struct TaskEditorView: View {
    enum Mode {
        case create(columnID: UUID?)
        case edit(TodoTask)
    }

    let mode: Mode
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    private var todoStore: TodoStore { TodoStore(context: context) }
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    @State private var text: String
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
            base = b
            self.columnID = task.columnID
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var resolved: (fields: ParsedInput, notes: String) {
        CaptureDraft.resolve(text: text, base: base, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing ? "编辑任务" : "新建任务").font(.headline)

            TokenStrip(fields: resolved.fields)

            MarkdownTextEditor(text: $text, onSave: save, onCancel: onClose)
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Text("第一行为标题 · ⌘↩ 保存 · esc 取消")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { onClose() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(resolved.fields.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
    }

    private func save() {
        let r = resolved
        let title = r.fields.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        var fields = r.fields
        fields.title = title

        let task: TodoTask
        switch mode {
        case .create:
            task = todoStore.add(fields, notes: r.notes)
        case .edit(let existing):
            existing.title = title
            existing.notes = r.notes
            existing.deadline = fields.deadline
            existing.priority = fields.priority
            existing.tags = fields.tags
            existing.recurrence = fields.recurrence
            task = existing
        }
        boardStore.setColumn(task, to: columnID)
        try? context.save()
        Task { await scheduler.schedule(for: task) }
        onClose()
    }
}

/// 编辑器上方的解析预览条:实时显示从第一行解析出的优先级/截止/标签/重复。
private struct TokenStrip: View {
    let fields: ParsedInput

    var body: some View {
        let chips = chipTexts
        HStack(spacing: 6) {
            ForEach(chips, id: \.self) { c in
                Text(c)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if chips.count <= 1 {
                Text("可在第一行用如「明天 !高 #工作」补充")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var chipTexts: [String] {
        var out: [String] = [Theme.priorityLabel(fields.priority)]
        if let d = fields.deadline {
            out.append(d.formatted(date: .abbreviated, time: .shortened))
        }
        out += fields.tags.map { "#\($0)" }
        if let r = fields.recurrence {
            out.append(Theme.recurrenceLabel(r))
        }
        return out
    }
}
```

- [ ] **Step 2: 删除 `TaskFormFields.swift`**

```bash
git rm WorkPanel/UI/TaskFormFields.swift
```

- [ ] **Step 3: 编译确认通过**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -quiet 2>&1 | tail -30`
Expected: BUILD SUCCEEDED。若报 `TaskFormFields` 仍被引用,搜索并处理:`rg -n TaskFormFields WorkPanel/`(预期无结果)。

- [ ] **Step 4: 跑全部单测确认未回归**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -30`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/TaskEditorView.swift
git commit -m "feat: rewrite TaskEditorView as single markdown textarea with token strip"
```

---

## Task 4: 看板「+ 添加任务」打开捕获面板;移除内联新增

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift`(替换第 124 行用法;删除 `addTaskField(_:)` 第 135–148 行与 `AddTaskField` 第 235–246 行)

- [ ] **Step 1: 把列底「+ 添加任务」改为打开面板的按钮**

In `WorkPanel/UI/BoardView.swift`, replace the call `addTaskField(column)`(约第 124 行)with:

```swift
            Button {
                NotificationCenter.default.post(
                    name: .openTaskEditor,
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
```

- [ ] **Step 2: 删除孤儿 `addTaskField(_:)`**

In `WorkPanel/UI/BoardView.swift`, delete the whole method(原第 135–148 行):

```swift
    private func addTaskField(_ column: BoardColumn) -> some View {
        AddTaskField { title in
            let parsed = InputParser().parse(title, now: .now, defaultPriority: AppSettings.defaultPriority)
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
```

- [ ] **Step 3: 删除孤儿 `AddTaskField` 视图**

In `WorkPanel/UI/BoardView.swift`, delete the whole private struct(原第 235–246 行):

```swift
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

- [ ] **Step 4: 编译确认通过**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -quiet 2>&1 | tail -30`
Expected: BUILD SUCCEEDED。`scheduler`/`InputParser` 在 BoardView 其它处仍使用(删除/完成任务的调度),不应报未使用。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat: board '+ 添加任务' opens capture panel; drop inline AddTaskField"
```

---

## 最终人工验证(运行 app)

- [ ] 列头 `+` 与列底「+ 添加任务」都打开同一个捕获面板。
- [ ] 面板只有一个文本域;输入多行,第一行作标题,⌘↩ 保存后任务标题/备注正确。
- [ ] 第一行输入「写周报 明天 !高 #工作」,token 条实时显示 高 / 明天时间 / #工作,保存后任务带对应字段。
- [ ] 正文输入 `## 标题`、`**粗体**`、`*斜体*`、`` `代码` ``、`- 列表`、`> 引用`,编辑时即时套样式(标记可见)。
- [ ] 编辑既有任务:首行=原标题、正文=原备注;不改首行 token 时,原截止/优先级/标签保留。
- [ ] esc 关闭面板;失焦自动关闭(既有行为)。

---

## Self-Review

- **Spec coverage:** 需求 #1 → Task 4;需求 #2(单文本域 + 第一行标题 + 解析合并)→ Task 1 + Task 3;需求 #3(行内实时渲染)→ Task 2 + Task 3 引用。删除 `TaskFormFields`/`AddTaskField` 清理 → Task 3/4。无遗漏。
- **Placeholder scan:** 无 TBD/TODO;每个代码步骤含完整代码。
- **Type consistency:** `CaptureDraft.resolve(text:base:now:calendar:) -> (fields: ParsedInput, notes: String)` 在 Task 1 定义,Task 3 按此签名调用;`MarkdownTextEditor(text:onSave:onCancel:)` 在 Task 2 定义,Task 3 按此调用;`TodoStore.add(_:notes:)`、`BoardStore.setColumn(_:to:)`、`Theme.priorityLabel(_:)`/`Theme.recurrenceLabel(_:)`/`Theme.panelRadius`、`AppSettings.defaultPriority`、`.openTaskEditor` 均为既有 API。
