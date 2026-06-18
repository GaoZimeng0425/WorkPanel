# 全量工作内容编辑器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个全局快捷键(⌘⌥L)打开一份把所有未完成任务渲染成的 Markdown 文档,用户在一个文本面板里改标题/备注/状态/优先级/标签、删除、新增,⌘↩ 一次性 diff 并落库。

**Architecture:** 纯函数层 `WorkLine` + `WorkDocument`(序列化 / 行解析 / 编辑锚点平移 / 对账成 ChangeSet)做全部风险逻辑,可脱离 UI/SwiftData 单测;`WorkDocApplier`(@MainActor)把 ChangeSet 落到 `ModelContext`;`AllTasksEditorView`(SwiftUI)是薄外壳,复用 `PanelController`(加可配置 `frameAutosaveName`)与共享 `markdownConfig`。身份靠「锚点 = 条目行起始字符偏移」,随 `onChange(of: text)` 纯函数平移,保存时按偏移精确匹配,从而保留时间等不在文本里的字段。

**Tech Stack:** Swift / SwiftUI / SwiftData / Swift Testing(`import Testing`)/ MarkdownEngine(`NativeTextViewWrapper`)/ KeyboardShortcuts。

## Global Constraints

- **默认 Actor 隔离 = MainActor**(`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`):纯类型的静态方法与存储属性需显式标 `nonisolated`,值类型标 `Sendable`(照搬 `InputParser`/`ParsedInput`/`CaptureDraft` 的写法)。
- **文件系统同步分组**:`WorkPanel/` 与 `WorkPanelTests/` 下新增文件自动纳入 target,**不要**编辑 `project.pbxproj`。
- **测试命令按套件单跑**(整包 `xcodebuild test` 可能卡死 testmanagerd):
  `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/<SuiteName>`
- **时间类字段不纳入本编辑器**:deadline / startDate / recurrence / urgencyOverride / snoozedUntil 不显示、不解析、保存时一律不动。
- **token 仅 `!优先级` 与 `#标签`**;`!中` 不在序列化时输出(medium 留空),仅 high→`!高`、low→`!低`。
- 复用既有 `Priority`、`TodoStore`、`BoardStore`、`TagStore`、`ReminderScheduler`、`PanelController`、`HotkeyManager`。

---

### Task 1: `WorkLine` 行解析器(纯函数)

只认 `!优先级` 与 `#标签`,其余文字(含「明天」「18:00」)一律作为标题字面量保留。

**Files:**
- Create: `WorkPanel/Parsing/WorkLine.swift`
- Test: `WorkPanelTests/WorkLineTests.swift`

**Interfaces:**
- Produces:
  - `struct WorkLine { nonisolated static func parse(_ text: String) -> Parsed }`
  - `extension WorkLine { struct Parsed: Equatable, Sendable { var title: String; var priority: Priority?; var tags: [String] } }`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
@testable import WorkPanel

struct WorkLineTests {
    @Test func extractsPriorityAndTags() {
        let r = WorkLine.parse("写周报 !高 #工作 #紧要")
        #expect(r.title == "写周报")
        #expect(r.priority == .high)
        #expect(r.tags == ["工作", "紧要"])
    }

    @Test func nonTokenWordsStayInTitle() {
        // 时间词不被吃掉,原样留在标题里
        let r = WorkLine.parse("明天 18:00 修复登录bug")
        #expect(r.title == "明天 18:00 修复登录bug")
        #expect(r.priority == nil)
        #expect(r.tags == [])
    }

    @Test func noPriorityTokenYieldsNil() {
        let r = WorkLine.parse("买菜 #生活")
        #expect(r.priority == nil)
        #expect(r.tags == ["生活"])
        #expect(r.title == "买菜")
    }

    @Test func bareHashIsTitleNotTag() {
        let r = WorkLine.parse("# 不是标签")
        #expect(r.tags == [])
        #expect(r.title == "# 不是标签")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkLineTests`
Expected: 编译失败(`WorkLine` 未定义)。

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 全量编辑器的行解析:仅识别 `!高/!中/!低` 优先级与 `#标签`,其余 token 作为标题字面量。
/// 与 InputParser 不同——本视图不解析时间/重复,故时间词留在标题里。纯函数,便于测试。
struct WorkLine {
    struct Parsed: Equatable, Sendable {
        nonisolated var title: String = ""
        nonisolated var priority: Priority? = nil
        nonisolated var tags: [String] = []
    }

    nonisolated private static let priorityMap: [String: Priority] = [
        "!高": .high, "!中": .medium, "!低": .low,
    ]

    nonisolated static func parse(_ text: String) -> Parsed {
        var result = Parsed()
        var titleWords: [String] = []
        let tokens = text
            .split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
            .map(String.init)
        for token in tokens {
            if let p = priorityMap[token] {
                result.priority = p
            } else if token.hasPrefix("#"), token.count > 1 {
                result.tags.append(String(token.dropFirst()))
            } else {
                titleWords.append(token)
            }
        }
        result.title = titleWords.joined(separator: " ")
        return result
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkLineTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/WorkLine.swift WorkPanelTests/WorkLineTests.swift
git commit -m "feat(edit-all): add WorkLine priority/tag line parser"
```

---

### Task 2: `WorkDocument` 值类型 + `serialize`(纯函数)

定义全量编辑器用到的值快照与文档类型,并实现「任务+列 → 文本 + 锚点」。

**Files:**
- Create: `WorkPanel/Parsing/WorkDocument.swift`
- Test: `WorkPanelTests/WorkDocumentSerializeTests.swift`

**Interfaces:**
- Produces(本任务定义,后续任务复用——精确名称与类型):
  - `struct WorkColumn: Equatable, Sendable { let id: UUID; var name: String }`
  - `struct WorkTaskSnapshot: Equatable, Sendable { let id: UUID; var title: String; var notes: String; var priority: Priority; var tags: [String]; var columnID: UUID?; var boardOrder: Int }`
  - `enum WorkDocument { struct Anchor: Equatable, Sendable { let id: UUID; var offset: Int } }`
  - `extension WorkDocument { nonisolated static func serialize(columns: [WorkColumn], tasks: [WorkTaskSnapshot]) -> (text: String, anchors: [Anchor]) }`
  - 未分类标题常量:`WorkDocument.uncategorizedHeading == "未分类"`
- 约定:`columns` 已按 `order` 排好序;`tasks` 含全部**未完成**任务(调用方过滤);每列内按 `boardOrder` 升序输出;末尾仅在存在 `columnID == nil` 任务时追加 `## 未分类`。条目行为 `- [ ] <title>[ !高|!低][ #tag…]`(medium 不输出 token);notes 每行前缀 4 个空格;锚点 `offset` = 条目行 `-` 的 Character 偏移。

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentSerializeTests {
    private let colA = UUID(), colB = UUID()
    private func columns() -> [WorkColumn] {
        [WorkColumn(id: colA, name: "计划中"), WorkColumn(id: colB, name: "开发中")]
    }

    @Test func groupsByColumnInOrderWithTokensAndNotes() {
        let t1 = WorkTaskSnapshot(id: UUID(), title: "写周报", notes: "汇总本周进展\n@张三",
                                  priority: .high, tags: ["工作"], columnID: colA, boardOrder: 0)
        let t2 = WorkTaskSnapshot(id: UUID(), title: "买菜", notes: "",
                                  priority: .medium, tags: [], columnID: colA, boardOrder: 1)
        let t3 = WorkTaskSnapshot(id: UUID(), title: "修复bug", notes: "",
                                  priority: .low, tags: [], columnID: colB, boardOrder: 0)
        let r = WorkDocument.serialize(columns: columns(), tasks: [t1, t2, t3])
        #expect(r.text == """
        ## 计划中
        - [ ] 写周报 !高 #工作
            汇总本周进展
            @张三
        - [ ] 买菜

        ## 开发中
        - [ ] 修复bug !低
        """)
    }

    @Test func uncategorizedHeadingOnlyWhenNilColumnTasksExist() {
        let none = WorkTaskSnapshot(id: UUID(), title: "随手记", notes: "",
                                    priority: .medium, tags: [], columnID: nil, boardOrder: 0)
        let r = WorkDocument.serialize(columns: columns(), tasks: [none])
        #expect(r.text.contains("## 未分类"))
        #expect(r.text.contains("- [ ] 随手记"))

        let empty = WorkDocument.serialize(columns: columns(), tasks: [])
        #expect(!empty.text.contains("## 未分类"))
    }

    @Test func anchorOffsetsPointAtItemDash() {
        let id1 = UUID()
        let t1 = WorkTaskSnapshot(id: id1, title: "写周报", notes: "",
                                  priority: .medium, tags: [], columnID: colA, boardOrder: 0)
        let r = WorkDocument.serialize(columns: columns(), tasks: [t1])
        let chars = Array(r.text)
        let anchor = r.anchors.first { $0.id == id1 }!
        #expect(chars[anchor.offset] == "-")            // 锚点落在条目行的 '-'
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentSerializeTests`
Expected: 编译失败(`WorkDocument` 未定义)。

- [ ] **Step 3: 实现**

```swift
import Foundation

struct WorkColumn: Equatable, Sendable {
    nonisolated let id: UUID
    nonisolated var name: String
}

struct WorkTaskSnapshot: Equatable, Sendable {
    nonisolated let id: UUID
    nonisolated var title: String
    nonisolated var notes: String
    nonisolated var priority: Priority
    nonisolated var tags: [String]
    nonisolated var columnID: UUID?
    nonisolated var boardOrder: Int
}

/// 全量编辑器的文档层:序列化 / 行解析 / 编辑锚点平移 / 对账。纯函数,脱离 UI 与 SwiftData。
enum WorkDocument {
    static let uncategorizedHeading = "未分类"

    struct Anchor: Equatable, Sendable {
        nonisolated let id: UUID
        nonisolated var offset: Int
    }

    nonisolated static func serialize(columns: [WorkColumn],
                                      tasks: [WorkTaskSnapshot]) -> (text: String, anchors: [Anchor]) {
        var text = ""
        var anchors: [Anchor] = []

        func emitGroup(heading: String, items: [WorkTaskSnapshot]) {
            if !text.isEmpty { text += "\n" }          // 组与组之间空一行
            text += "## " + heading + "\n"
            for task in items.sorted(by: { $0.boardOrder < $1.boardOrder }) {
                anchors.append(Anchor(id: task.id, offset: text.count))   // '-' 的偏移
                text += "- [ ] " + itemLine(task) + "\n"
                if !task.notes.isEmpty {                       // 空备注不输出缩进空行
                    for noteLine in task.notes.split(separator: "\n", omittingEmptySubsequences: false) {
                        text += "    " + noteLine + "\n"
                    }
                }
            }
        }

        for col in columns {
            let items = tasks.filter { $0.columnID == col.id }
            guard !items.isEmpty else { continue }
            emitGroup(heading: col.name, items: items)
        }
        let orphans = tasks.filter { $0.columnID == nil }
        if !orphans.isEmpty { emitGroup(heading: uncategorizedHeading, items: orphans) }

        if text.hasSuffix("\n") { text.removeLast() }   // 去掉末尾换行,文档更干净
        return (text, anchors)
    }

    nonisolated private static func itemLine(_ task: WorkTaskSnapshot) -> String {
        var parts = [task.title]
        switch task.priority {
        case .high: parts.append("!高")
        case .low:  parts.append("!低")
        case .medium: break                              // medium 不输出 token
        }
        parts.append(contentsOf: task.tags.map { "#" + $0 })
        return parts.joined(separator: " ")
    }
}
```

> 注:`Priority` 为现有 enum(`.high/.medium/.low`)。若 `switch` 提示非穷尽,补 `@unknown default` 或确认其仅三例(现为三例)。

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentSerializeTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/WorkDocument.swift WorkPanelTests/WorkDocumentSerializeTests.swift
git commit -m "feat(edit-all): add WorkDocument value types and serialize"
```

---

### Task 3: 编辑锚点平移 `computeEdit` + `shift`(纯函数)

**Files:**
- Modify: `WorkPanel/Parsing/WorkDocument.swift`(在 `enum WorkDocument` 内追加)
- Test: `WorkPanelTests/WorkDocumentShiftTests.swift`

**Interfaces:**
- Produces:
  - `extension WorkDocument { struct Edit: Equatable, Sendable { var loc: Int; var oldLen: Int; var newLen: Int } }`
  - `extension WorkDocument { nonisolated static func computeEdit(old: [Character], new: [Character]) -> Edit }`
  - `extension WorkDocument { nonisolated static func shift(anchors: [Anchor], by edit: Edit) -> [Anchor] }`
- 语义:锚点在编辑区间末尾及之后 → 偏移加 `newLen-oldLen`;严格在编辑起点之前 → 不动;落在 `[loc, loc+oldLen)` 区间内 → 溶解(从数组移除)。

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentShiftTests {
    private func edit(_ old: String, _ new: String) -> WorkDocument.Edit {
        WorkDocument.computeEdit(old: Array(old), new: Array(new))
    }

    @Test func computeEditFindsSingleSpan() {
        #expect(edit("abcdef", "abXcdef") == .init(loc: 2, oldLen: 0, newLen: 1))   // 在 2 处插入 X
        #expect(edit("abcdef", "abdef") == .init(loc: 2, oldLen: 1, newLen: 0))      // 删 c
        #expect(edit("abc", "abc") == .init(loc: 3, oldLen: 0, newLen: 0))           // 无变化
    }

    @Test func anchorAfterEditShifts() {
        let e = WorkDocument.Edit(loc: 0, oldLen: 0, newLen: 3)   // 在最前插入 3 字
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 10)], by: e)
        #expect(out == [.init(id: idA, offset: 13)])
    }

    @Test func anchorBeforeEditUnchanged() {
        let e = WorkDocument.Edit(loc: 20, oldLen: 2, newLen: 5)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 10)], by: e)
        #expect(out == [.init(id: idA, offset: 10)])
    }

    @Test func editInsideTitleKeepsAnchor() {
        // 锚点在行首 offset=5,在标题中部(offset 9)改字 → 锚点不动
        let e = WorkDocument.Edit(loc: 9, oldLen: 1, newLen: 4)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 5)], by: e)
        #expect(out == [.init(id: idA, offset: 5)])
    }

    @Test func fullLineDeletionDissolvesAnchor() {
        // 删除区间 [5, 15) 覆盖行首锚点 offset=5 → 溶解
        let e = WorkDocument.Edit(loc: 5, oldLen: 10, newLen: 0)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 5)], by: e)
        #expect(out.isEmpty)
    }

    @Test func insertionAtAnchorPushesAnchorRight() {
        // 在行首正前方插入(loc==offset)→ '-' 右移,锚点跟着右移
        let e = WorkDocument.Edit(loc: 5, oldLen: 0, newLen: 2)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 5)], by: e)
        #expect(out == [.init(id: idA, offset: 7)])
    }

    private let idA = UUID()
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentShiftTests`
Expected: 编译失败。

- [ ] **Step 3: 实现(追加到 `enum WorkDocument`)**

```swift
    struct Edit: Equatable, Sendable {
        nonisolated var loc: Int
        nonisolated var oldLen: Int
        nonisolated var newLen: Int
    }

    /// 单段编辑检测:公共前缀长度 = loc,公共后缀长度从两端各扣除 loc 之后取。
    nonisolated static func computeEdit(old: [Character], new: [Character]) -> Edit {
        var p = 0
        let minLen = min(old.count, new.count)
        while p < minLen && old[p] == new[p] { p += 1 }
        var s = 0
        while s < (minLen - p) && old[old.count - 1 - s] == new[new.count - 1 - s] { s += 1 }
        return Edit(loc: p, oldLen: old.count - p - s, newLen: new.count - p - s)
    }

    nonisolated static func shift(anchors: [Anchor], by edit: Edit) -> [Anchor] {
        let delta = edit.newLen - edit.oldLen
        let regionEnd = edit.loc + edit.oldLen
        return anchors.compactMap { a in
            if a.offset >= regionEnd { return Anchor(id: a.id, offset: a.offset + delta) }
            if a.offset < edit.loc { return a }
            return nil                                   // 落在删除区间内 → 溶解
        }
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentShiftTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/WorkDocument.swift WorkPanelTests/WorkDocumentShiftTests.swift
git commit -m "feat(edit-all): add anchor edit-tracking (computeEdit + shift)"
```

---

### Task 4: `WorkDocument.parse`(文本 → 块,纯函数)

**Files:**
- Modify: `WorkPanel/Parsing/WorkDocument.swift`
- Test: `WorkPanelTests/WorkDocumentParseTests.swift`

**Interfaces:**
- Produces:
  - `extension WorkDocument { struct Block: Equatable, Sendable { var columnID: UUID?; var title: String; var priority: Priority?; var tags: [String]; var notes: String; var completed: Bool; var offset: Int } }`
  - `extension WorkDocument { nonisolated static func parse(text: String, columns: [WorkColumn]) -> [Block] }`
- 约定:`## X` 行按名匹配 `columns` 设当前列(匹配 `未分类` 或未知名 → `columnID = nil`);`- [ ] ` / `- [x] ` 行起新块(`offset` = 行首 Character 偏移,`completed` 由 `[x]`/`[X]` 判定,正文交 `WorkLine.parse`);**缩进**(以空格/Tab 起头)的非空行 = 当前块 notes(剥首部空白,逐行用 `\n` 拼接);空行与无缩进的杂行忽略。空标题块也照常产出(由 reconcile 决定丢弃/删除)。

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentParseTests {
    private let colA = UUID()
    private func columns() -> [WorkColumn] { [WorkColumn(id: colA, name: "计划中")] }

    @Test func parsesItemsHeadingsNotes() {
        let text = """
        ## 计划中
        - [ ] 写周报 !高 #工作
            汇总进展
            第二行备注
        - [x] 买菜
        """
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(blocks.count == 2)
        #expect(blocks[0].columnID == colA)
        #expect(blocks[0].title == "写周报")
        #expect(blocks[0].priority == .high)
        #expect(blocks[0].tags == ["工作"])
        #expect(blocks[0].notes == "汇总进展\n第二行备注")
        #expect(blocks[0].completed == false)
        #expect(blocks[1].title == "买菜")
        #expect(blocks[1].completed == true)
        #expect(blocks[1].notes == "")
    }

    @Test func unknownHeadingMapsToNilColumn() {
        let text = "## 未分类\n- [ ] 随手记"
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(blocks[0].columnID == nil)
    }

    @Test func offsetPointsAtDash() {
        let text = "## 计划中\n- [ ] 写周报"
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(Array(text)[blocks[0].offset] == "-")
    }

    @Test func roundTripsThroughSerialize() {
        let id = UUID()
        let snap = WorkTaskSnapshot(id: id, title: "写周报", notes: "备注一行",
                                    priority: .high, tags: ["工作"], columnID: colA, boardOrder: 0)
        let (text, anchors) = WorkDocument.serialize(columns: columns(), tasks: [snap])
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(blocks.count == 1)
        #expect(blocks[0].offset == anchors[0].offset)   // 锚点 ↔ 块偏移对齐
        #expect(blocks[0].title == "写周报")
        #expect(blocks[0].notes == "备注一行")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentParseTests`
Expected: 编译失败。

- [ ] **Step 3: 实现(追加到 `enum WorkDocument`)**

```swift
    struct Block: Equatable, Sendable {
        nonisolated var columnID: UUID?
        nonisolated var title: String
        nonisolated var priority: Priority?
        nonisolated var tags: [String]
        nonisolated var notes: String
        nonisolated var completed: Bool
        nonisolated var offset: Int
    }

    nonisolated static func parse(text: String, columns: [WorkColumn]) -> [Block] {
        var blocks: [Block] = []
        var currentColumn: UUID? = nil
        var offset = 0
        var noteLines: [String] = []                     // 累积当前块的 notes

        func flushNotes() {
            if !blocks.isEmpty {
                blocks[blocks.count - 1].notes = noteLines.joined(separator: "\n")
            }
            noteLines = []
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let lineStart = offset
            offset += line.count + 1                      // +1 = 换行符;末行多算 1 无妨

            if line.hasPrefix("## ") {
                flushNotes()
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentColumn = columns.first { $0.name == name }?.id
            } else if let rest = itemBody(line) {
                flushNotes()
                let parsed = WorkLine.parse(rest.text)
                blocks.append(Block(columnID: currentColumn,
                                    title: parsed.title, priority: parsed.priority, tags: parsed.tags,
                                    notes: "", completed: rest.completed, offset: lineStart))
            } else if let first = line.first, first == " " || first == "\t" {
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if !trimmed.isEmpty { noteLines.append(String(trimmed)) }
            }
            // 其余(空行 / 无缩进杂行)忽略
        }
        flushNotes()
        return blocks
    }

    /// 识别 `- [ ] x` / `- [x] x` / `- [X] x`,返回正文与勾选态;非条目行返回 nil。
    nonisolated private static func itemBody(_ line: String) -> (text: String, completed: Bool)? {
        for (prefix, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] {
            if line.hasPrefix(prefix) { return (String(line.dropFirst(prefix.count)), done) }
        }
        return nil
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentParseTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/WorkDocument.swift WorkPanelTests/WorkDocumentParseTests.swift
git commit -m "feat(edit-all): add WorkDocument.parse (text to blocks)"
```

---

### Task 5: `WorkDocument.reconcile`(块+锚点+快照 → ChangeSet,纯函数)

**Files:**
- Modify: `WorkPanel/Parsing/WorkDocument.swift`
- Test: `WorkPanelTests/WorkDocumentReconcileTests.swift`

**Interfaces:**
- Produces:
  - `extension WorkDocument { struct CreateSpec: Equatable, Sendable { var title: String; var notes: String; var priority: Priority; var tags: [String]; var columnID: UUID?; var order: Int } }`
  - `extension WorkDocument { struct UpdateSpec: Equatable, Sendable { var id: UUID; var title: String; var notes: String; var priority: Priority; var tags: [String]; var columnID: UUID?; var order: Int; var complete: Bool } }`
  - `extension WorkDocument { struct ChangeSet: Equatable, Sendable { var creates: [CreateSpec]; var updates: [UpdateSpec]; var deletes: [UUID] } }`
  - `extension WorkDocument { nonisolated static func reconcile(blocks: [Block], anchors: [Anchor], liveTasks: [WorkTaskSnapshot]) -> ChangeSet }`
- 语义:
  - 先丢弃**空标题**块(`title` 去空白为空)。
  - 块偏移命中存活锚点且该 id ∈ `liveTasks` → **update**(priority 缺省保留:`block.priority ?? live.priority`;tags 缺省保留:`block.tags.isEmpty ? live.tags : block.tags`),否则 → **create**(priority 缺省 `.medium`,tags 用块的)。
  - `order` = 该块在其所属 `columnID` 分组内按文档顺序的序号(0,1,2…)。
  - **deletes** = `liveTasks` 的 id − 被命中的 id(误删防护:外部新建任务不在 `liveTasks` 快照里,绝不会被删)。

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentReconcileTests {
    private let colA = UUID()

    private func liveSnap(_ id: UUID, _ title: String, priority: Priority = .medium,
                          tags: [String] = [], column: UUID? = nil, order: Int = 0) -> WorkTaskSnapshot {
        WorkTaskSnapshot(id: id, title: title, notes: "", priority: priority, tags: tags,
                         columnID: column, boardOrder: order)
    }

    @Test func updatesMatchedKeepsTimeFieldsImplicitly() {
        let id = UUID()
        let blocks = [WorkDocument.Block(columnID: colA, title: "写周报改", priority: nil, tags: [],
                                         notes: "新备注", completed: false, offset: 0)]
        let anchors = [WorkDocument.Anchor(id: id, offset: 0)]
        let live = [liveSnap(id, "写周报", priority: .high, tags: ["工作"], column: colA)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: anchors, liveTasks: live)
        #expect(cs.creates.isEmpty)
        #expect(cs.deletes.isEmpty)
        #expect(cs.updates == [.init(id: id, title: "写周报改", notes: "新备注",
                                     priority: .high, tags: ["工作"],    // 缺省保留
                                     columnID: colA, order: 0, complete: false)])
    }

    @Test func newBlockBecomesCreate() {
        let blocks = [WorkDocument.Block(columnID: colA, title: "新任务", priority: .low, tags: ["x"],
                                         notes: "", completed: false, offset: 0)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [], liveTasks: [])
        #expect(cs.updates.isEmpty)
        #expect(cs.creates == [.init(title: "新任务", notes: "", priority: .low, tags: ["x"],
                                     columnID: colA, order: 0)])
    }

    @Test func removedLineBecomesDelete() {
        let id = UUID()
        // 文档里没有这条任务的块(锚点已溶解)→ 删除
        let cs = WorkDocument.reconcile(blocks: [], anchors: [], liveTasks: [liveSnap(id, "买菜")])
        #expect(cs.deletes == [id])
    }

    @Test func externalTaskNotInSnapshotIsNeverDeleted() {
        // liveTasks 是打开时快照;外部新建的任务不在其中 → 不会出现在 deletes
        let cs = WorkDocument.reconcile(blocks: [], anchors: [], liveTasks: [])
        #expect(cs.deletes.isEmpty)
    }

    @Test func emptyTitleBlockSkipped() {
        let blocks = [WorkDocument.Block(columnID: colA, title: "   ", priority: nil, tags: [],
                                         notes: "", completed: false, offset: 0)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [], liveTasks: [])
        #expect(cs.creates.isEmpty && cs.updates.isEmpty && cs.deletes.isEmpty)
    }

    @Test func orderIsPerColumnDocumentOrder() {
        let blocks = [
            WorkDocument.Block(columnID: colA, title: "一", priority: nil, tags: [], notes: "", completed: false, offset: 0),
            WorkDocument.Block(columnID: nil,  title: "二", priority: nil, tags: [], notes: "", completed: false, offset: 10),
            WorkDocument.Block(columnID: colA, title: "三", priority: nil, tags: [], notes: "", completed: false, offset: 20),
        ]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [], liveTasks: [])
        let orders = Dictionary(uniqueKeysWithValues: cs.creates.map { ($0.title, ($0.columnID, $0.order)) })
        #expect(orders["一"]! == (colA, 0))
        #expect(orders["三"]! == (colA, 1))   // 同列内第二个
        #expect(orders["二"]! == (nil, 0))    // nil 列各自计数
    }

    @Test func checkedBoxMarksComplete() {
        let id = UUID()
        let blocks = [WorkDocument.Block(columnID: colA, title: "买菜", priority: nil, tags: [],
                                         notes: "", completed: true, offset: 0)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [.init(id: id, offset: 0)],
                                        liveTasks: [liveSnap(id, "买菜", column: colA)])
        #expect(cs.updates.first?.complete == true)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentReconcileTests`
Expected: 编译失败。

- [ ] **Step 3: 实现(追加到 `enum WorkDocument`)**

```swift
    struct CreateSpec: Equatable, Sendable {
        nonisolated var title: String; nonisolated var notes: String
        nonisolated var priority: Priority; nonisolated var tags: [String]
        nonisolated var columnID: UUID?; nonisolated var order: Int
    }
    struct UpdateSpec: Equatable, Sendable {
        nonisolated var id: UUID; nonisolated var title: String; nonisolated var notes: String
        nonisolated var priority: Priority; nonisolated var tags: [String]
        nonisolated var columnID: UUID?; nonisolated var order: Int; nonisolated var complete: Bool
    }
    struct ChangeSet: Equatable, Sendable {
        nonisolated var creates: [CreateSpec]
        nonisolated var updates: [UpdateSpec]
        nonisolated var deletes: [UUID]
    }

    nonisolated static func reconcile(blocks: [Block], anchors: [Anchor],
                                      liveTasks: [WorkTaskSnapshot]) -> ChangeSet {
        let liveByID = Dictionary(uniqueKeysWithValues: liveTasks.map { ($0.id, $0) })
        let idByOffset = Dictionary(anchors.map { ($0.offset, $0.id) }, uniquingKeysWith: { a, _ in a })

        var creates: [CreateSpec] = []
        var updates: [UpdateSpec] = []
        var matched: Set<UUID> = []
        var orderByColumn: [UUID?: Int] = [:]                 // 每列(含 nil)文档顺序计数

        for block in blocks {
            guard !block.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let order = orderByColumn[block.columnID, default: 0]
            orderByColumn[block.columnID] = order + 1

            if let id = idByOffset[block.offset], let live = liveByID[id] {
                matched.insert(id)
                updates.append(UpdateSpec(
                    id: id,
                    title: block.title.trimmingCharacters(in: .whitespaces),
                    notes: block.notes,
                    priority: block.priority ?? live.priority,                 // 缺省保留
                    tags: block.tags.isEmpty ? live.tags : block.tags,          // 缺省保留
                    columnID: block.columnID, order: order, complete: block.completed))
            } else {
                creates.append(CreateSpec(
                    title: block.title.trimmingCharacters(in: .whitespaces),
                    notes: block.notes,
                    priority: block.priority ?? .medium,
                    tags: block.tags,
                    columnID: block.columnID, order: order))
            }
        }
        let deletes = liveTasks.map(\.id).filter { !matched.contains($0) }
        return ChangeSet(creates: creates, updates: updates, deletes: deletes)
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocumentReconcileTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/WorkDocument.swift WorkPanelTests/WorkDocumentReconcileTests.swift
git commit -m "feat(edit-all): add WorkDocument.reconcile (blocks to ChangeSet)"
```

---

### Task 6: `WorkDocApplier` 落库(@MainActor)

把 `ChangeSet` 应用到 `ModelContext`:create / update(含 `[x]` 完成)/ delete(带 Tombstone + 取消提醒),注册标签,直接赋 `columnID`+`boardOrder`(文档顺序),最后一次 `saveTracking()`。

**Files:**
- Create: `WorkPanel/Store/WorkDocApplier.swift`
- Test: `WorkPanelTests/WorkDocApplierTests.swift`

**Interfaces:**
- Consumes: `WorkDocument.ChangeSet`、`WorkDocument.CreateSpec/UpdateSpec`、`TodoStore`、`BoardStore`(不直接用 move,直接赋 `boardOrder`)、`TagStore`、`ReminderScheduler`、`TodoTask`。
- Produces: `@MainActor final class WorkDocApplier { init(context: ModelContext); func apply(_ changes: WorkDocument.ChangeSet) }`
- 约定:update 按 id 取现有 `TodoTask`(全量 fetch 建 `[id: task]`),设 title/notes/priority/tags/columnID/boardOrder;若 `complete` 且尚未完成 → 调 `TodoStore.complete`(自动处理重复后继 + completedAt),对返回的后继 occurrence 排提醒。delete 调 `ReminderScheduler.cancel` + `TodoStore.delete`。create 用 `TodoStore.add(ParsedInput, notes:)` 再赋列与序号。所有用到的标签经 `TagStore.register(names:)` 注册。

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct WorkDocApplierTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, Tag.self, Tombstone.self, DayPlan.self,
            configurations: config)
        return ModelContext(container)
    }

    @Test func createInsertsTaskWithColumnAndTags() throws {
        let ctx = try makeContext()
        let col = UUID()
        let cs = WorkDocument.ChangeSet(
            creates: [.init(title: "新任务", notes: "备注", priority: .high, tags: ["工作"],
                            columnID: col, order: 0)],
            updates: [], deletes: [])
        WorkDocApplier(context: ctx).apply(cs)

        let tasks = try ctx.fetch(FetchDescriptor<TodoTask>())
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "新任务")
        #expect(tasks[0].notes == "备注")
        #expect(tasks[0].priority == .high)
        #expect(tasks[0].columnID == col)
        #expect(tasks[0].boardOrder == 0)
        let tags = try ctx.fetch(FetchDescriptor<Tag>())
        #expect(tags.map(\.name).contains("工作"))
    }

    @Test func updateChangesFieldsButKeepsDeadline() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "旧标题", priority: .low)
        let deadline = Date(timeIntervalSince1970: 1_900_000_000)
        task.deadline = deadline
        ctx.insert(task)
        let cs = WorkDocument.ChangeSet(creates: [],
            updates: [.init(id: task.id, title: "新标题", notes: "n", priority: .high, tags: [],
                            columnID: nil, order: 3, complete: false)],
            deletes: [])
        WorkDocApplier(context: ctx).apply(cs)

        #expect(task.title == "新标题")
        #expect(task.priority == .high)
        #expect(task.boardOrder == 3)
        #expect(task.deadline == deadline)             // 时间字段不动
        #expect(task.isCompleted == false)
    }

    @Test func completeMarksDone() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "买菜")
        ctx.insert(task)
        let cs = WorkDocument.ChangeSet(creates: [],
            updates: [.init(id: task.id, title: "买菜", notes: "", priority: .medium, tags: [],
                            columnID: nil, order: 0, complete: true)],
            deletes: [])
        WorkDocApplier(context: ctx).apply(cs)
        #expect(task.isCompleted == true)
        #expect(task.completedAt != nil)
    }

    @Test func deleteRemovesTaskAndLeavesTombstone() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "删我")
        ctx.insert(task)
        let id = task.id
        let cs = WorkDocument.ChangeSet(creates: [], updates: [], deletes: [id])
        WorkDocApplier(context: ctx).apply(cs)

        #expect((try ctx.fetch(FetchDescriptor<TodoTask>())).isEmpty)
        let tombstones = try ctx.fetch(FetchDescriptor<Tombstone>())
        #expect(tombstones.contains { $0.id == id })
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocApplierTests`
Expected: 编译失败(`WorkDocApplier` 未定义)。

- [ ] **Step 3: 实现**

```swift
import Foundation
import SwiftData

/// 把 WorkDocument.ChangeSet 落到 ModelContext。直接赋 columnID/boardOrder(文档顺序),
/// 复用 TodoStore(add/complete/delete)、TagStore(标签注册)、ReminderScheduler(后继提醒)。
@MainActor
final class WorkDocApplier {
    private let context: ModelContext
    private let todoStore: TodoStore
    private let tagStore: TagStore
    private let scheduler = ReminderScheduler()

    init(context: ModelContext) {
        self.context = context
        self.todoStore = TodoStore(context: context)
        self.tagStore = TagStore(context: context)
    }

    func apply(_ changes: WorkDocument.ChangeSet) {
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        // 新建
        for spec in changes.creates {
            var fields = ParsedInput()
            fields.title = spec.title
            fields.priority = spec.priority
            fields.tags = spec.tags
            let task = todoStore.add(fields, notes: spec.notes)
            task.columnID = spec.columnID
            task.boardOrder = spec.order
        }

        // 更新
        for spec in changes.updates {
            guard let task = byID[spec.id] else { continue }
            task.title = spec.title
            task.notes = spec.notes
            task.priority = spec.priority
            task.tags = spec.tags
            task.columnID = spec.columnID
            task.boardOrder = spec.order
            if spec.complete && !task.isCompleted {
                if let follow = todoStore.complete(task) {
                    Task { await scheduler.schedule(for: follow) }
                }
            }
        }

        // 删除
        for id in changes.deletes {
            guard let task = byID[id] else { continue }
            scheduler.cancel(for: task)
            todoStore.delete(task)
        }

        // 标签注册
        let names = changes.creates.flatMap(\.tags) + changes.updates.flatMap(\.tags)
        tagStore.register(names: names)

        try? context.saveTracking()
    }
}
```

> 实现前用 codegraph 确认 `ReminderScheduler.cancel(for:)` 与 `schedule(for:)` 的签名(`ReminderSchedulerTests` 里有用法);若 `cancel` 为 async,改成 `Task { await scheduler.cancel(for: task) }`。

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/WorkDocApplierTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/WorkDocApplier.swift WorkPanelTests/WorkDocApplierTests.swift
git commit -m "feat(edit-all): add WorkDocApplier to persist ChangeSet"
```

---

### Task 7: 抽出共享 `markdownConfig`

把 `TaskEditorView.markdownConfig` 提到共享位置,供新视图与 `TaskEditorView` 共用,行为保持不变。

**Files:**
- Create: `WorkPanel/UI/DesignSystem/SharedMarkdown.swift`
- Modify: `WorkPanel/UI/Tasks/TaskEditorView.swift:194-214`(删掉私有 `markdownConfig`,改引用共享)

**Interfaces:**
- Produces: `enum SharedMarkdown { @MainActor static var editorConfig: MarkdownEditorConfiguration { ... } }`(内容为现 `TaskEditorView.markdownConfig` 的整段,逐字搬运,含 `import MarkdownEngine`、Theme 颜色)。
- `TaskEditorView` 内 `NativeTextViewWrapper(text: $text, configuration: markdownConfig, ...)` 改为 `configuration: SharedMarkdown.editorConfig`。

- [ ] **Step 1: 新建共享文件**(把 `TaskEditorView.markdownConfig` 的实现逐字搬过来)

```swift
import SwiftUI
import AppKit
import MarkdownEngine

/// 共享的 MarkdownEngine 编辑器配置(noir 调色 + 收紧字号/内边距)。
/// 由 TaskEditorView 与 AllTasksEditorView 共用,保证两处着色一致。
enum SharedMarkdown {
    @MainActor static var editorConfig: MarkdownEditorConfiguration {
        let orange = NSColor(Theme.accent)
        var theme = MarkdownEditorTheme.default
        theme.bodyText = NSColor(Theme.textPrimary)
        theme.mutedText = orange
        theme.disabledText = NSColor(Theme.textMuted)
        theme.headingMarker = orange
        theme.link = orange
        theme.strikethroughColor = NSColor(Theme.textTertiary)

        var config = MarkdownEditorConfiguration.default
        config.theme = theme
        config.textInsets = TextInsets(horizontal: 14, vertical: 12)
        config.headings.fontMultipliers = [1.5, 1.3, 1.15, 1.0, 0.9, 0.8]
        config.overscroll = OverscrollPolicy(percent: 0.1, maxPoints: 40, minPoints: 0)
        config.lists.autoClosePairsEnabled = false
        config.lists.indentPerLevel = 0
        return config
    }
}
```

- [ ] **Step 2: 改 `TaskEditorView`**:删除其 `private var markdownConfig: MarkdownEditorConfiguration { ... }`(`WorkPanel/UI/Tasks/TaskEditorView.swift:194-214`),并把 `body` 里的 `configuration: markdownConfig` 改为 `configuration: SharedMarkdown.editorConfig`。

- [ ] **Step 3: 编译 + 回归既有测试**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。
Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/CaptureDraftTests`
Expected: PASS(确认未破坏捕获相关回归)。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/DesignSystem/SharedMarkdown.swift WorkPanel/UI/Tasks/TaskEditorView.swift
git commit -m "refactor(editor): extract shared markdown editor config"
```

---

### Task 8: `PanelController` 支持可配置 `frameAutosaveName`

**Files:**
- Modify: `WorkPanel/UI/Panels/PanelController.swift:8`(把 `frameAutosaveName` 改成 init 注入)

**Interfaces:**
- Produces: `PanelController(frameAutosaveName: String = "WorkPanelTaskEditorFrame")`;默认值保证现有捕获面板行为不变。

- [ ] **Step 1: 改造**:把 `private let frameAutosaveName = "WorkPanelTaskEditorFrame"` 改为存储属性 + init:

```swift
    private let frameAutosaveName: String

    init(frameAutosaveName: String = "WorkPanelTaskEditorFrame") {
        self.frameAutosaveName = frameAutosaveName
    }
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED(`AppDelegate` 里 `PanelController()` 仍合法,用默认名)。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/Panels/PanelController.swift
git commit -m "refactor(panel): make frameAutosaveName configurable"
```

---

### Task 9: `AllTasksEditorView`(SwiftUI 外壳)

打开即序列化全部未完成任务;`onChange(of: text)` 平移锚点;⌘↩ 解析→对账→落库;esc/取消丢弃。

**Files:**
- Create: `WorkPanel/UI/Tasks/AllTasksEditorView.swift`

**Interfaces:**
- Consumes: `WorkDocument`(serialize/computeEdit/shift/parse/reconcile)、`WorkDocApplier`、`WorkColumn`/`WorkTaskSnapshot`、`SharedMarkdown.editorConfig`、`NativeTextViewWrapper`、`Theme`、`NoirPillButtonStyle`。
- Produces: `struct AllTasksEditorView: View { let onClose: () -> Void; init(onClose: @escaping () -> Void) }`

- [ ] **Step 1: 实现**

```swift
import SwiftUI
import SwiftData
import MarkdownEngine

/// 全量工作内容编辑器:把所有未完成任务渲染成一份 markdown 文档,⌘↩ 一次性 diff 落库。
/// 仅编辑 标题/备注/状态/优先级(!高 !低)/标签(#x);时间类字段不显示、保存时原样保留。
struct AllTasksEditorView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TodoTask]
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    @State private var text = ""
    @State private var anchors: [WorkDocument.Anchor] = []
    @State private var openSnapshot: [WorkTaskSnapshot] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全部工作内容")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            NativeTextViewWrapper(text: $text, configuration: SharedMarkdown.editorConfig, fontSize: 13)
                .frame(minHeight: 240, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surfaceSubtle))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.strokeStrong, lineWidth: 0.7))

            HStack {
                Text("## 状态分组 · 缩进=备注 · !高/!低 · #标签 · ⌘↩ 保存 · esc 取消")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Button("取消") { onClose() }
                    .buttonStyle(NoirPillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(18)
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
            .stroke(Theme.stroke, lineWidth: 1))
        .preferredColorScheme(.dark)
        .onAppear { load() }
        .onChange(of: text) { old, new in
            let edit = WorkDocument.computeEdit(old: Array(old), new: Array(new))
            anchors = WorkDocument.shift(anchors: anchors, by: edit)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let cols = columns.map { WorkColumn(id: $0.id, name: $0.name) }
        let snaps = allTasks.filter { !$0.isCompleted }.map {
            WorkTaskSnapshot(id: $0.id, title: $0.title, notes: $0.notes, priority: $0.priority,
                             tags: $0.tags, columnID: $0.columnID, boardOrder: $0.boardOrder)
        }
        let r = WorkDocument.serialize(columns: cols, tasks: snaps)
        text = r.text
        anchors = r.anchors
        openSnapshot = snaps
    }

    private func save() {
        let cols = columns.map { WorkColumn(id: $0.id, name: $0.name) }
        let blocks = WorkDocument.parse(text: text, columns: cols)
        let changes = WorkDocument.reconcile(blocks: blocks, anchors: anchors, liveTasks: openSnapshot)
        WorkDocApplier(context: context).apply(changes)
        onClose()
    }
}
```

> `onChange(of: text)` 的初始 `text=""` → 首次 `load()` 赋值会触发一次 `onChange`,此时 `anchors` 已由 `load()` 设好,`computeEdit("", fullText)` 得 `loc=0,oldLen=0,newLen=N`,`shift` 把所有锚点 `+N`——会错位。**解决**:`load()` 里赋值顺序为先设 `text` 再设 `anchors`,且在 `onChange` 内用 `guard loaded else { return }` 跳过加载态的首次回调。实现时把 `load()` 改为先 `text = r.text`,再 `anchors = r.anchors`;并在 `onChange` 首行加 `guard loaded, !text.isEmpty || !old.isEmpty else { return }` 不可靠——**改用显式标志**:新增 `@State private var applyingLoad = false`,`load()` 里包 `applyingLoad = true; text = r.text; anchors = r.anchors; applyingLoad = false`,`onChange` 首行 `guard !applyingLoad else { return }`。

- [ ] **Step 2: 按上述注记修正 load/onChange 竞态**(加 `applyingLoad` 标志,`onChange` 内 `guard !applyingLoad else { return }`)。

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/Tasks/AllTasksEditorView.swift
git commit -m "feat(edit-all): add AllTasksEditorView shell"
```

---

### Task 10: 快捷键接线(⌘⌥L)

**Files:**
- Modify: `WorkPanel/System/HotkeyManager.swift`
- Modify: `WorkPanel/WorkPanelApp.swift`(`AppDelegate`)

**Interfaces:**
- Consumes: `AllTasksEditorView`、`PanelController(frameAutosaveName:)`。
- Produces: `KeyboardShortcuts.Name.toggleAllEdit`(默认 ⌘⌥L)、`HotkeyManager.registerAllEdit(_:)`、`AppDelegate.toggleAllEdit()`。

- [ ] **Step 1: HotkeyManager 增加快捷键**

```swift
    static let toggleAllEdit = Self(
        "toggleAllEdit",
        default: .init(.l, modifiers: [.command, .option])
    )
```
并在 `enum HotkeyManager` 内加:
```swift
    static func registerAllEdit(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleAllEdit, action: handler)
    }
```

- [ ] **Step 2: AppDelegate 接线**:把 `private let panel = PanelController()` 改为 `private let panel = PanelController(frameAutosaveName: "WorkPanelTaskEditorFrame")`,新增 `private let allEdit = PanelController(frameAutosaveName: "WorkPanelAllEditFrame")`;在 `applicationDidFinishLaunching` 的 `HotkeyManager.registerBoard {...}` 之后加:

```swift
        HotkeyManager.registerAllEdit { [weak self] in self?.toggleAllEdit() }
```
并新增方法:
```swift
    private func toggleAllEdit() {
        if allEdit.isVisible { allEdit.hide(); return }
        allEdit.show {
            AllTasksEditorView(onClose: { [weak self] in self?.allEdit.hide() })
                .modelContainer(SharedModel.container)
        }
    }
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/System/HotkeyManager.swift WorkPanel/WorkPanelApp.swift
git commit -m "feat(edit-all): wire ⌘⌥L hotkey to AllTasksEditorView"
```

---

### Task 11: 手动验证(全链路)

全局快捷键无法用 XCUITest 可靠触发,且 markdown 文本域无法被合成驱动(见项目记忆),故全链路靠手动冒烟;逻辑正确性已由 Task 1–6 单测覆盖。

**Files:** 无(仅运行)

- [ ] **Step 1: 跑全部新单测套件**

```bash
for s in WorkLineTests WorkDocumentSerializeTests WorkDocumentShiftTests WorkDocumentParseTests WorkDocumentReconcileTests WorkDocApplierTests; do
  xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/$s || break
done
```
Expected: 每个套件 PASS。

- [ ] **Step 2: 运行 App 手动冒烟**

```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS'
open ~/Library/Developer/Xcode/DerivedData/WorkPanel-*/Build/Products/Debug/WorkPanel.app
```
依次验证:
1. 按 **⌘⌥L** → 弹出「全部工作内容」面板,按列分组列出所有未完成任务;medium 任务无 `!` token,high/low 有。
2. 改一条标题 → ⌘↩ → 再按 ⌘⌥L,改动在;deadline 仍在(开 ⌘⌥J 单任务编辑器核对其时间未变)。
3. 把一条挪到另一个 `## 标题` 下 → ⌘↩ → 看板(⌘⌥K)里该任务已换列。
4. 末尾新敲一行 `- [ ] 临时任务 !高` → ⌘↩ → 出现在对应列。
5. 删掉一整行 → ⌘↩ → 该任务消失(看板核对)。
6. 勾选某行 `- [x]` → ⌘↩ → 该任务标记完成,下次 ⌘⌥L 不再出现。
7. 按 **esc** 关闭后再开,未保存的改动已丢弃。

- [ ] **Step 3: 收尾提交(如手动验证发现并修了小问题)**

```bash
git add -A && git commit -m "fix(edit-all): manual smoke-test fixes"
```

---

## Self-Review

**Spec coverage:**
- 入口/⌘⌥L/面板复用 → Task 8、10。✔
- 文档格式(分组、未分类、token 仅 !优先级/#标签、title-first、notes 缩进、[x] 完成)→ Task 2、4、serialize/parse 测试。✔
- 时间字段不纳入、原样保留 → Task 5(reconcile 不碰时间)、Task 6(applier update 不写 deadline)+ 对应测试。✔
- 缺省即保留(priority/tags)→ Task 5 测试 `updatesMatchedKeepsTimeFieldsImplicitly`。✔
- 身份/锚点平移/合并/拆分/空标题/误删防护 → Task 3、5 测试。✔
- 落库(TodoStore/BoardStore 序号/TagStore/ReminderScheduler/Tombstone)→ Task 6。✔
- 共享 markdownConfig、不复用 TaskEditorView/InputParser → Task 7、9。✔
- 测试矩阵 → Task 1–6 单测 + Task 11 手动冒烟。✔

**Placeholder scan:** 无 TBD/TODO;每个代码步骤含完整可编译代码。Task 6 对 `ReminderScheduler.cancel/schedule` 签名留了「实现前用 codegraph 确认」的明确动作(非占位)。

**Type consistency:** `WorkColumn`/`WorkTaskSnapshot`/`Anchor`/`Edit`/`Block`/`CreateSpec`/`UpdateSpec`/`ChangeSet` 全程同名;`serialize`/`parse`/`computeEdit`/`shift`/`reconcile`/`WorkDocApplier.apply` 签名在定义任务与消费任务(9)间一致。`PanelController(frameAutosaveName:)` 在 Task 8 定义、Task 10 消费一致。
