# 工作 item 时间范围 + 甘特图 tab 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给每个工作 item 增加可空的"开始时间"(与现有 `deadline` 共同构成时间范围),并新增一个"甘特"看板 tab,把任务按时间范围画成可拖动/拉伸的横条。

**Architecture:** 特性 1 给 `TodoTask` 加一个可空 `startDate`,并在同步 DTO、MCP DTO/handler、任务编辑器四处镜像处理。特性 2 新增 `BoardViewMode.gantt` 透镜,渲染走"自绘冻结行列"方案:纯日期↔坐标/拖拽换算抽进可单测的 `GanttGeometry`,视图层做冻结行列布局 + `DragGesture` 拖动/拉伸,提交时写回模型。

**Tech Stack:** Swift / SwiftUI / SwiftData;Swift Testing(`import Testing`);macOS 部署目标 26.5(可用 `onScrollGeometryChange` 等新滚动 API)。

**全局约定:**
- 测试运行(逐套件,避免全 bundle `xcodebuild test` 卡死 testmanagerd):
  `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/<Suite> 2>&1 | tail -30`
- 构建验证:
  `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -30`
- 新文件放在 `WorkPanel/` 或 `WorkPanelTests/` 下即自动纳入(文件系统同步组),**不要手改 `project.pbxproj`**。
- `saveTracking()` 会自动把改动过的 `Timestamped` 模型的 `modifiedAt` 打成 now;故各处**无需**手动设 `modifiedAt`。

---

### Task 1: `TodoTask` 增加 `startDate`

**Files:**
- Modify: `WorkPanel/Models/TodoTask.swift`
- Test: `WorkPanelTests/TodoTaskTests.swift`

- [ ] **Step 1: 写失败测试**

在 `TodoTaskTests` 结构体内追加:

```swift
@Test func startDateDefaultsNilAndIsSettable() {
    let t = TodoTask(title: "带开始")
    #expect(t.startDate == nil)
    let d = Date(timeIntervalSince1970: 1000)
    t.startDate = d
    #expect(t.startDate == d)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoTaskTests 2>&1 | tail -30`
Expected: 编译失败 —— `value of type 'TodoTask' has no member 'startDate'`。

- [ ] **Step 3: 加字段**

在 `WorkPanel/Models/TodoTask.swift` 的属性区,`var deadline: Date?` 下一行加:

```swift
    var startDate: Date?
```

`startDate` 是 `Optional`,SwiftData 轻量迁移会把老数据置 nil,无需默认值标注。

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoTaskTests 2>&1 | tail -30`
Expected: PASS(全套件绿)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Models/TodoTask.swift WorkPanelTests/TodoTaskTests.swift
git commit -m "feat(model): add optional startDate to TodoTask"
```

---

### Task 2: 同步 `startDate`(SyncTaskDTO)

**Files:**
- Modify: `WorkPanel/Sync/SyncDocument.swift:3-38`(`SyncTaskDTO`)
- Test: `WorkPanelTests/SyncDocumentTests.swift`

- [ ] **Step 1: 写失败测试**

在 `SyncDocumentTests` 内追加两个测试:

```swift
@Test func taskDTORoundTripsStartDate() throws {
    let t = TodoTask(title: "带范围")
    t.startDate = Date(timeIntervalSince1970: 60)
    t.deadline = Date(timeIntervalSince1970: 100)
    let back = try SyncDocument.decoder.decode(
        SyncTaskDTO.self, from: try SyncDocument.encoder.encode(SyncTaskDTO(t)))
    #expect(back.startDate == Date(timeIntervalSince1970: 60))
}

@Test func taskDTOMissingStartDateDecodesAsNil() throws {
    // 模拟旧版本文档:JSON 里没有 startDate 键 → 解码回 nil
    let t = TodoTask(title: "无开始")           // startDate 为 nil
    let data = try SyncDocument.encoder.encode(SyncTaskDTO(t))
    #expect(!(String(data: data, encoding: .utf8) ?? "").contains("startDate"))
    let back = try SyncDocument.decoder.decode(SyncTaskDTO.self, from: data)
    #expect(back.startDate == nil)
}
```

> 说明:`JSONEncoder` 默认会省略值为 nil 的 `Optional` 键,故 nil 时 JSON 不含 `startDate`,旧文档解码也按缺键→nil 处理,向后兼容。`currentSchemaVersion` 保持 1。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncDocumentTests 2>&1 | tail -30`
Expected: 编译失败 —— `SyncTaskDTO` 无 `startDate` 成员。

- [ ] **Step 3: 给 DTO 加字段并搬运**

在 `WorkPanel/Sync/SyncDocument.swift` 的 `SyncTaskDTO` 中:

属性区(`var deadline: Date?` 下一行)加:

```swift
    var startDate: Date?
```

`init(_ t: TodoTask)` 体内,`deadline = t.deadline` 同一处补:

```swift
        startDate = t.startDate
```

`apply(to t: TodoTask)` 体内,`t.deadline = deadline` 同一处补:

```swift
        t.startDate = startDate
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncDocumentTests 2>&1 | tail -30`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/SyncDocument.swift WorkPanelTests/SyncDocumentTests.swift
git commit -m "feat(sync): carry startDate through SyncTaskDTO"
```

---

### Task 3: MCP 暴露 `startDate`(输出 + create/update 读写)

**Files:**
- Modify: `WorkPanel/MCP/TaskDTO.swift:33-60`(`TaskDTO`)
- Modify: `WorkPanel/MCP/MCPToolHandlers.swift`(`createTask`、`updateTask`)
- Test: `WorkPanelTests/TaskDTOTests.swift`、`WorkPanelTests/MCPToolHandlersTests.swift`

- [ ] **Step 1: 写失败测试(DTO 输出)**

在 `TaskDTOTests` 内追加:

```swift
@Test func dtoIncludesStartDate() {
    let start = Date(timeIntervalSince1970: 1000)
    let task = TodoTask(title: "带开始")
    task.startDate = start
    let dto = TaskDTO(task, columnName: nil)
    #expect(dto.startDate == ISO8601Date.string(start))

    let none = TaskDTO(TodoTask(title: "无开始"), columnName: nil)
    #expect(none.startDate == nil)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TaskDTOTests 2>&1 | tail -30`
Expected: 编译失败 —— `TaskDTO` 无 `startDate`。

- [ ] **Step 3: 给 TaskDTO 加字段**

在 `WorkPanel/MCP/TaskDTO.swift` 的 `TaskDTO` 中:

属性区 `let deadline: String?` 下一行加:

```swift
    let startDate: String?
```

`init(_ task:columnName:now:)` 体内,`deadline = task.deadline.map(ISO8601Date.string)` 下一行加:

```swift
        startDate = task.startDate.map(ISO8601Date.string)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TaskDTOTests 2>&1 | tail -30`
Expected: PASS。

- [ ] **Step 5: 写失败测试(create/update 读写)**

在 `MCPToolHandlersTests` 内追加(沿用文件已有的 `makeHandlers()` / `decodeTask()` 辅助):

```swift
@Test func createTaskAcceptsStartDate() async throws {
    let (h, _, _) = try makeHandlers()
    let start = ISO8601Date.string(Date(timeIntervalSince1970: 1000))
    let json = try await h.call("create_task", ["title": "带开始", "startDate": .string(start)])
    #expect(try decodeTask(json).startDate == start)
}

@Test func updateTaskSetsAndClearsStartDate() async throws {
    let (h, ctx, _) = try makeHandlers()
    let t = TodoTask(title: "改开始")
    ctx.insert(t); try ctx.save()

    let start = ISO8601Date.string(Date(timeIntervalSince1970: 2000))
    let set = try await h.call("update_task", ["id": .string(t.id.uuidString), "startDate": .string(start)])
    #expect(try decodeTask(set).startDate == start)

    let cleared = try await h.call("update_task", ["id": .string(t.id.uuidString), "startDate": .null])
    #expect(try decodeTask(cleared).startDate == nil)
}
```

- [ ] **Step 6: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -30`
Expected: FAIL —— `startDate` 未被写入,断言不符(create 返回 nil;update set 返回 nil)。

- [ ] **Step 7: 在 handler 里处理 `startDate`**

在 `WorkPanel/MCP/MCPToolHandlers.swift` 的 `createTask(_:)` 中,紧接现有 `deadline` 解析块(`if args.contains("deadline") { ... parsed.deadline = date }`)之后、`// validate columnID` 之前,插入局部变量解析(注意 `ParsedInput` 不含 startDate,故单独取):

```swift
        var startDate: Date? = nil
        if args.contains("startDate"), args["startDate"]?.isNull != true {
            guard let s = args["startDate"]?.stringValue, let date = ISO8601Date.date(s) else {
                throw ToolError.badArgument("Invalid 'startDate'")
            }
            startDate = date
        }
```

再在该函数内 `let task = todo.add(parsed, notes: notes)` 之后、`if let targetColumn` 之前插入:

```swift
        task.startDate = startDate
```

在 `updateTask(_:)` 中,紧接现有 `deadline` 处理块(`if args.contains("deadline") { ... }`)之后插入:

```swift
        if args.contains("startDate") {
            if args["startDate"]?.isNull == true { task.startDate = nil }
            else if let s = args["startDate"]?.stringValue, let d = ISO8601Date.date(s) { task.startDate = d }
            else { throw ToolError.badArgument("Invalid 'startDate'") }
        }
```

- [ ] **Step 8: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -30`
然后:`... -only-testing:WorkPanelTests/TaskDTOTests 2>&1 | tail -30`
Expected: 两套件 PASS。

- [ ] **Step 9: 提交**

```bash
git add WorkPanel/MCP/TaskDTO.swift WorkPanel/MCP/MCPToolHandlers.swift WorkPanelTests/TaskDTOTests.swift WorkPanelTests/MCPToolHandlersTests.swift
git commit -m "feat(mcp): expose and accept startDate"
```

---

### Task 4: 任务编辑器加"开始"控件

**Files:**
- Modify: `WorkPanel/UI/Tasks/TaskEditorView.swift`
- 无单测(SwiftUI 视图);验证靠构建 + 手测。

- [ ] **Step 1: 加状态**

在 `@State private var deadline: Date?`(约第 29 行)下一行加:

```swift
    @State private var startDate: Date?
    @State private var showingStartPicker = false
```

- [ ] **Step 2: init 两分支初始化**

在 `init` 的 `.create` 分支,`_deadline = State(initialValue: nil)` 下一行加:

```swift
            _startDate = State(initialValue: nil)
```

在 `.edit(let task)` 分支,`_deadline = State(initialValue: task.deadline)` 下一行加:

```swift
            _startDate = State(initialValue: task.startDate)
```

- [ ] **Step 3: controls 加一行"开始"(在"时间"之上)**

在 `controls` 计算属性中,把 `controlRow("时间") { deadlineControl }` 这一行替换为下面两行(开始在上):

```swift
            controlRow("开始") { startControl }
            controlRow("时间") { deadlineControl }
```

- [ ] **Step 4: 加 startControl 及其绑定/默认值**

在 `deadlineControl` 计算属性之后,加入与 deadline 对称的实现:

```swift
    private var startBinding: Binding<Date> {
        Binding(get: { startDate ?? defaultStart() }, set: { startDate = $0 })
    }

    private func defaultStart() -> Date {
        let cal = Calendar.current
        let hour = cal.dateComponents([.year, .month, .day, .hour], from: .now)
        return cal.date(from: hour) ?? .now
    }

    @ViewBuilder
    private var startControl: some View {
        if startDate != nil {
            HStack(spacing: 8) {
                Button { showingStartPicker = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar").font(.system(size: 10))
                        Text(startBinding.wrappedValue.formatted(date: .abbreviated, time: .shortened))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .noirPickerPill()
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingStartPicker, arrowEdge: .bottom) {
                    NoirDatePicker(date: startBinding)
                        .padding(12)
                        .frame(width: 250)
                        .background(Theme.panelBottom)
                        .preferredColorScheme(.dark)
                }
                Button { startDate = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button { startDate = defaultStart() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.plus")
                    Text("添加开始")
                }
                .noirPickerPill()
            }
            .buttonStyle(.plain)
        }
    }
```

> 注:`noirPickerPill()` 与清除按钮样式照搬现有 `deadlineControl`;若 `deadlineControl` 的清除按钮图标/写法略有出入,以现有 deadline 实现为准对齐(保持两控件视觉一致)。

- [ ] **Step 5: save() 写回 startDate**

在 `save()` 中,`switch mode { ... }` 结束后、`boardStore.setColumn(task, to: columnID)` 之前插入:

```swift
        task.startDate = startDate
```

- [ ] **Step 6: 构建验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -30`
Expected: BUILD SUCCEEDED。手测:编辑器出现"开始"行,可设/清开始时间,保存后重开仍在。

- [ ] **Step 7: 提交**

```bash
git add WorkPanel/UI/Tasks/TaskEditorView.swift
git commit -m "feat(editor): add start-time control to task editor"
```

---

### Task 5: 看板列调色板(Theme)

**Files:**
- Modify: `WorkPanel/UI/DesignSystem/Theme.swift`
- Test: `WorkPanelTests/ThemeTests.swift`

- [ ] **Step 1: 写失败测试**

在 `ThemeTests` 内追加:

```swift
@Test func columnColorWrapsByModulo() {
    let n = Theme.columnPalette.count
    #expect(n >= 4)
    #expect(Theme.columnColor(order: 0) == Theme.columnPalette[0])
    #expect(Theme.columnColor(order: n) == Theme.columnPalette[0])       // 取模回绕
    #expect(Theme.columnColor(order: n + 1) == Theme.columnPalette[1])
    #expect(Theme.columnColor(order: -1) == Theme.columnPalette[n - 1])  // 负数也安全
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ThemeTests 2>&1 | tail -30`
Expected: 编译失败 —— `Theme` 无 `columnPalette` / `columnColor`。

- [ ] **Step 3: 加调色板与取色函数**

在 `WorkPanel/UI/DesignSystem/Theme.swift` 的"语义色"区(`tag`/`deadline` 那几行附近)加入:

```swift
    // MARK: 看板列调色板(甘特图按列着色;列 order 取模索引)
    nonisolated static let columnPalette: [Color] = [
        Color(red: 0.30, green: 0.65, blue: 1.0),  // 蓝
        Color(red: 0.36, green: 0.76, blue: 0.43),  // 绿
        Color(red: 1.0,  green: 0.70, blue: 0.25),  // 琥珀
        Color(red: 0.73, green: 0.55, blue: 1.0),  // 紫
        Color(red: 1.0,  green: 0.45, blue: 0.55),  // 粉
        Color(red: 0.40, green: 0.80, blue: 0.80),  // 青
    ]

    nonisolated static func columnColor(order: Int) -> Color {
        let n = columnPalette.count
        return columnPalette[((order % n) + n) % n]
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ThemeTests 2>&1 | tail -30`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/DesignSystem/Theme.swift WorkPanelTests/ThemeTests.swift
git commit -m "feat(theme): add board-column color palette"
```

---

### Task 6: 甘特纯几何/排序 helper(`GanttGeometry`)

**Files:**
- Create: `WorkPanel/UI/Board/GanttGeometry.swift`
- Test: `WorkPanelTests/GanttGeometryTests.swift`

- [ ] **Step 1: 写失败测试**

新建 `WorkPanelTests/GanttGeometryTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct GanttGeometryTests {
    // 用 UTC + 固定起点,避免本地时区影响断言。
    private func geo(dayWidth: CGFloat = 40) -> GanttGeometry {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)   // 1970-01-01 00:00 UTC
        return GanttGeometry(timelineStart: start, dayWidth: dayWidth, calendar: cal)
    }
    private func day(_ n: Int, hour: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(n * 86400 + hour * 3600))
    }

    @Test func dayIndexAndX() {
        let g = geo()
        #expect(g.dayIndex(for: day(0, hour: 23)) == 0)   // 同一天向下取整
        #expect(g.dayIndex(for: day(3)) == 3)
        #expect(g.x(for: day(3)) == 120)                  // 3 * 40
    }

    @Test func barFrameFullRange() {
        let g = geo()
        let f = g.barFrame(start: day(1), end: day(3))
        #expect(f?.x == 40)
        #expect(f?.width == 120)   // 1..3 含两端 = 3 天 * 40
    }

    @Test func barFrameDeadlineOnlyIsSingleDay() {
        let g = geo()
        let f = g.barFrame(start: nil, end: day(2))
        #expect(f?.x == 80)
        #expect(f?.width == 40)
    }

    @Test func barFrameStartAfterEndCollapsesToStartDay() {
        let g = geo()
        let f = g.barFrame(start: day(5), end: day(2))
        #expect(f?.x == 200)
        #expect(f?.width == 40)
    }

    @Test func barFrameNilWhenUnscheduled() {
        #expect(geo().barFrame(start: nil, end: nil) == nil)
    }

    @Test func daysDeltaRounds() {
        let g = geo(dayWidth: 40)
        #expect(g.daysDelta(translationX: 95) == 2)    // 95/40 = 2.375 → 2
        #expect(g.daysDelta(translationX: -60) == -2)  // -1.5 → -2
    }

    @Test func shiftedKeepsDuration() {
        let g = geo()
        let r = g.shifted(start: day(1), end: day(3), byDays: 2)
        #expect(r.start == day(3))
        #expect(r.end == day(5))
    }

    @Test func resizedStartClampsToEndDay() {
        let g = geo()
        // start 推到 end 之后 → 夹到与 end 同一天
        let s = g.resizedStart(start: day(1, hour: 9), end: day(2), byDays: 5)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(cal.isDate(s, inSameDayAs: day(2)))
    }

    @Test func resizedEndClampsToStartDay() {
        let g = geo()
        let e = g.resizedEnd(start: day(3), end: day(4, hour: 9), byDays: -10)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(cal.isDate(e, inSameDayAs: day(3)))
    }

    @Test func partitionSortsScheduledAndIsolatesUnscheduled() {
        let a = GanttRow(id: UUID(), start: day(5), end: day(6))
        let b = GanttRow(id: UUID(), start: nil,    end: day(2))   // 只有 deadline
        let c = GanttRow(id: UUID(), start: nil,    end: nil)      // 未排期
        let (scheduled, unscheduled) = GanttGeometry.partition([a, b, c])
        #expect(scheduled.map(\.id) == [b.id, a.id])   // 按有效开始升序(b 的 deadline 早于 a 的 start)
        #expect(unscheduled.map(\.id) == [c.id])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/GanttGeometryTests 2>&1 | tail -30`
Expected: 编译失败 —— 找不到 `GanttGeometry` / `GanttRow`。

- [ ] **Step 3: 实现 GanttGeometry**

新建 `WorkPanel/UI/Board/GanttGeometry.swift`:

```swift
import Foundation
import CoreGraphics

/// 甘特图一行的纯数据键:仅起止两个可空时间,无 SwiftData 依赖,便于单测排序/分区。
struct GanttRow: Equatable, Identifiable {
    let id: UUID
    let start: Date?
    let end: Date?

    var effectiveStart: Date? { start ?? end }
    var isScheduled: Bool { start != nil || end != nil }
}

/// 甘特图纯几何 / 日期换算。无 SwiftUI、无 TodoTask 依赖,成员 nonisolated 以便在非隔离上下文单测。
struct GanttGeometry: Sendable {
    nonisolated let timelineStart: Date    // 时间轴第 0 天的当天 0 点
    nonisolated let dayWidth: CGFloat
    nonisolated let calendar: Calendar

    nonisolated init(timelineStart: Date, dayWidth: CGFloat, calendar: Calendar = .current) {
        self.calendar = calendar
        self.timelineStart = calendar.startOfDay(for: timelineStart)
        self.dayWidth = dayWidth
    }

    /// 从 timelineStart 起的整天序号(向下取整到天)。
    nonisolated func dayIndex(for date: Date) -> Int {
        calendar.dateComponents([.day], from: timelineStart,
                                to: calendar.startOfDay(for: date)).day ?? 0
    }

    nonisolated func x(for date: Date) -> CGFloat {
        CGFloat(dayIndex(for: date)) * dayWidth
    }

    /// 条的 (x, width)。start/end 皆 nil → 返回 nil(未排期)。
    /// 单边、或 start 当天晚于 end 当天 → 该有效日期当天单格(1 天宽)。
    nonisolated func barFrame(start: Date?, end: Date?) -> (x: CGFloat, width: CGFloat)? {
        switch (start, end) {
        case (nil, nil):
            return nil
        case let (s?, e?):
            if calendar.startOfDay(for: e) >= calendar.startOfDay(for: s) {
                let days = dayIndex(for: e) - dayIndex(for: s) + 1
                return (x(for: s), CGFloat(days) * dayWidth)
            }
            return (x(for: s), dayWidth)        // start 在 end 之后 → 单格
        case let (s?, nil):
            return (x(for: s), dayWidth)
        case let (nil, e?):
            return (x(for: e), dayWidth)
        }
    }

    /// 横向位移换算成整天数(四舍五入)。
    nonisolated func daysDelta(translationX: CGFloat) -> Int {
        Int((translationX / dayWidth).rounded())
    }

    /// 平移:start 与 end 同移 days 天,保持时长(nil 的保持 nil)。
    nonisolated func shifted(start: Date?, end: Date?, byDays days: Int)
        -> (start: Date?, end: Date?) {
        (start.map { calendar.date(byAdding: .day, value: days, to: $0)! },
         end.map { calendar.date(byAdding: .day, value: days, to: $0)! })
    }

    /// 拖左端点改 start;不得越过 end 当天(最小 1 天)。
    nonisolated func resizedStart(start: Date, end: Date?, byDays days: Int) -> Date {
        let moved = calendar.date(byAdding: .day, value: days, to: start)!
        guard let end else { return moved }
        if calendar.startOfDay(for: moved) > calendar.startOfDay(for: end) {
            return clampDay(of: moved, toDayOf: end)
        }
        return moved
    }

    /// 拖右端点改 end;不得早于 start 当天(最小 1 天)。
    nonisolated func resizedEnd(start: Date?, end: Date, byDays days: Int) -> Date {
        let moved = calendar.date(byAdding: .day, value: days, to: end)!
        guard let start else { return moved }
        if calendar.startOfDay(for: moved) < calendar.startOfDay(for: start) {
            return clampDay(of: moved, toDayOf: start)
        }
        return moved
    }

    /// 保留 date 的时刻,只把"年月日"换成 ref 的当天。
    nonisolated private func clampDay(of date: Date, toDayOf ref: Date) -> Date {
        let t = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0,
                             second: t.second ?? 0, of: ref) ?? ref
    }

    /// 排期任务按有效开始升序;未排期(start/end 皆 nil)单列,保持输入顺序。
    nonisolated static func partition(_ rows: [GanttRow])
        -> (scheduled: [GanttRow], unscheduled: [GanttRow]) {
        let scheduled = rows.filter(\.isScheduled)
            .sorted { ($0.effectiveStart ?? .distantPast) < ($1.effectiveStart ?? .distantPast) }
        let unscheduled = rows.filter { !$0.isScheduled }
        return (scheduled, unscheduled)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/GanttGeometryTests 2>&1 | tail -30`
Expected: PASS(11 个测试全绿)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/Board/GanttGeometry.swift WorkPanelTests/GanttGeometryTests.swift
git commit -m "feat(gantt): add pure GanttGeometry (date/coord math + sort)"
```

---

### Task 7: 接入"甘特" tab(BoardViewMode + BoardView)

**Files:**
- Modify: `WorkPanel/Models/BoardViewMode.swift`
- Modify: `WorkPanel/UI/Board/BoardView.swift:55-63`(content 分发)、`:111-119`(icon)
- Test: `WorkPanelTests/BoardViewModeReviewTests.swift`

> 本任务结尾会引用 `GanttLensView`(Task 8 创建)。为保证本任务可独立构建,先在 BoardView 里临时分发到一个占位;Task 8 落地后替换。或按 subagent 流程把 Task 7、8 连续执行。这里采用**先建空壳再补实现**:本任务先创建一个最小可编译的 `GanttLensView` 空壳,Task 8 填充其 body。

- [ ] **Step 1: 写失败测试**

在 `BoardViewModeReviewTests` 内追加:

```swift
@Test func allCasesIncludesGantt() {
    #expect(BoardViewMode.allCases.contains(.gantt))
    #expect(BoardViewMode.gantt.label == "甘特")
    #expect(BoardViewMode(rawValue: "gantt") == .gantt)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardViewModeReviewTests 2>&1 | tail -30`
Expected: 编译失败 —— `BoardViewMode` 无 `gantt`。

- [ ] **Step 3: 加枚举 case 与 label**

在 `WorkPanel/Models/BoardViewMode.swift`:

`case kanban, matrix, today, priority, review` 改为:

```swift
    case kanban, matrix, today, priority, review, gantt
```

`label` 的 switch 内,`case .review: "复盘"` 下一行加:

```swift
        case .gantt:    "甘特"
```

- [ ] **Step 4: 建 GanttLensView 空壳(本任务可编译)**

新建 `WorkPanel/UI/Board/GanttLensView.swift`(Task 8 会填充 body):

```swift
import SwiftUI
import SwiftData

/// 甘特透镜:任务按时间范围画成横条,可拖动/拉伸改起止。
struct GanttLensView: View {
    var body: some View {
        Text("甘特图")
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: BoardView 分发 + 图标**

在 `WorkPanel/UI/Board/BoardView.swift` 的 `content` switch 中,`case .review: ReviewLensView()` 下一行加:

```swift
        case .gantt:    GanttLensView()
```

在 `icon(for:)` 的 switch 中,`case .review: "chart.bar"` 下一行加:

```swift
        case .gantt:    "chart.bar.xaxis"
```

- [ ] **Step 6: 跑测试 + 构建**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardViewModeReviewTests 2>&1 | tail -30`
Expected: PASS。
Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -30`
Expected: BUILD SUCCEEDED;运行可见末尾多出"甘特" tab,内容为占位文案。

- [ ] **Step 7: 提交**

```bash
git add WorkPanel/Models/BoardViewMode.swift WorkPanel/UI/Board/BoardView.swift WorkPanel/UI/Board/GanttLensView.swift WorkPanelTests/BoardViewModeReviewTests.swift
git commit -m "feat(board): add gantt tab (placeholder lens)"
```

---

### Task 8: 实现 GanttLensView(冻结行列 + 拖动/拉伸)

**Files:**
- Modify: `WorkPanel/UI/Board/GanttLensView.swift`(填充 Task 7 的空壳)
- 无单测(SwiftUI 视图 + 拖拽,XCUITest 不可驱动);验证靠构建 + 手测。核心数学已由 Task 6 单测覆盖。

**布局要点:**
- 左侧任务名列固定宽 `nameW`,放在水平滚动**之外** → 横向冻结。
- 顶部日期头放在垂直滚动**之外**,其水平偏移用 `onScrollGeometryChange` 读到的 `scrollX` 镜像 → 纵向冻结、横向与条网格同步。
- 名列与条网格同处一个**垂直** `ScrollView`,故纵向一起滚。
- `dayWidth = (可视宽 - nameW) / 14`(两周正好填满,横向可滑)。
- 时间轴从 `min(今天, 最早起止)` 当天 到 `max(今天+13天, 最晚起止)` 当天。

- [ ] **Step 1: 用完整实现替换空壳**

把 `WorkPanel/UI/Board/GanttLensView.swift` 整体替换为:

```swift
import SwiftUI
import SwiftData

/// 甘特透镜:未完成任务按时间范围画成横条,可拖动整条平移、拖端点改时长;
/// 未排期(无起止)任务列在底部,点击打开编辑器。
struct GanttLensView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    private let scheduler = ReminderScheduler()

    private let nameW: CGFloat = 132
    private let rowH: CGFloat = 30
    private let rowGap: CGFloat = 6
    private let headerH: CGFloat = 26
    private let cal = Calendar.current

    @State private var scrollX: CGFloat = 0

    // 未完成任务 → GanttRow,分区
    private var partitioned: (scheduled: [GanttRow], unscheduled: [GanttRow]) {
        let rows = tasks.filter { !$0.isCompleted }
            .map { GanttRow(id: $0.id, start: $0.startDate, end: $0.deadline) }
        return GanttGeometry.partition(rows)
    }

    // 时间轴范围:[firstDay, lastDay],含两端
    private var timelineBounds: (start: Date, days: Int) {
        let scheduled = partitioned.scheduled
        let today = cal.startOfDay(for: .now)
        var minDay = today, maxDay = cal.date(byAdding: .day, value: 13, to: today)!
        for r in scheduled {
            for d in [r.start, r.end].compactMap({ $0 }) {
                let day = cal.startOfDay(for: d)
                if day < minDay { minDay = day }
                if day > maxDay { maxDay = day }
            }
        }
        let days = (cal.dateComponents([.day], from: minDay, to: maxDay).day ?? 0) + 1
        return (minDay, days)
    }

    var body: some View {
        GeometryReader { geo in
            let bounds = timelineBounds
            let dayW = max((geo.size.width - nameW) / 14, 28)
            let contentW = CGFloat(bounds.days) * dayW
            let g = GanttGeometry(timelineStart: bounds.start, dayWidth: dayW, calendar: cal)
            let scheduled = partitioned.scheduled
            let unscheduled = partitioned.unscheduled

            VStack(spacing: 0) {
                header(g: g, days: bounds.days, dayW: dayW, contentW: contentW,
                       viewportW: geo.size.width)
                Rectangle().fill(Theme.stroke).frame(height: 1)

                ScrollView(.vertical, showsIndicators: false) {
                    if scheduled.isEmpty && unscheduled.isEmpty {
                        emptyText("还没有任务")
                    }
                    HStack(alignment: .top, spacing: 0) {
                        // 冻结名列
                        VStack(spacing: rowGap) {
                            ForEach(scheduled) { nameCell($0) }
                        }
                        .frame(width: nameW, alignment: .leading)

                        // 横向滚动的条网格
                        ScrollView(.horizontal, showsIndicators: true) {
                            ZStack(alignment: .topLeading) {
                                gridLines(days: bounds.days, dayW: dayW)
                                    .frame(width: contentW)
                                VStack(spacing: rowGap) {
                                    ForEach(scheduled) { row in
                                        barLane(row, g: g, contentW: contentW)
                                    }
                                }
                            }
                            .frame(width: contentW, alignment: .topLeading)
                        }
                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                            scrollX = x
                        }
                    }
                    .padding(.top, rowGap)

                    if !unscheduled.isEmpty {
                        unscheduledSection(unscheduled)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: 头 / 网格

    private func header(g: GanttGeometry, days: Int, dayW: CGFloat,
                        contentW: CGFloat, viewportW: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameW, height: headerH)
            HStack(spacing: 0) {
                ForEach(0..<days, id: \.self) { i in
                    dateLabel(dayOffset: i, base: g.timelineStart)
                        .frame(width: dayW, height: headerH)
                }
            }
            .frame(width: contentW, alignment: .leading)
            .offset(x: -scrollX)
            .frame(width: max(viewportW - nameW, 0), alignment: .leading)
            .clipped()
        }
    }

    private func dateLabel(dayOffset: Int, base: Date) -> some View {
        let date = cal.date(byAdding: .day, value: dayOffset, to: base)!
        let isToday = cal.isDateInToday(date)
        return VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Theme.accentText : Theme.textSecondary)
        }
    }

    private func gridLines(days: Int, dayW: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<days, id: \.self) { i in
                Rectangle()
                    .fill(cal.isDateInToday(cal.date(byAdding: .day, value: i, to: timelineBounds.start)!)
                          ? Theme.accent.opacity(0.06) : Color.clear)
                    .frame(width: dayW)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.stroke.opacity(0.5)).frame(width: 1)
                    }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: 行

    private func nameCell(_ row: GanttRow) -> some View {
        Text(title(for: row.id))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: rowH, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .onTapGesture { openEditor(row.id) }
    }

    private func barLane(_ row: GanttRow, g: GanttGeometry, contentW: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: contentW, height: rowH)
            if let frame = g.barFrame(start: row.start, end: row.end) {
                GanttBar(
                    title: title(for: row.id),
                    color: color(for: row.id),
                    baseX: frame.x,
                    baseWidth: frame.width,
                    dayWidth: g.dayWidth,
                    height: rowH,
                    onMove: { dx in commitMove(row, g: g, translationX: dx) },
                    onResizeLeft: { dx in commitResizeLeft(row, g: g, translationX: dx) },
                    onResizeRight: { dx in commitResizeRight(row, g: g, translationX: dx) },
                    onTap: { openEditor(row.id) }
                )
            }
        }
        .frame(height: rowH)
    }

    private func unscheduledSection(_ rows: [GanttRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("未排期")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 10)
            ForEach(rows) { row in
                Text(title(for: row.id))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(Theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { openEditor(row.id) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyText(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    // MARK: 数据辅助

    private func task(_ id: UUID) -> TodoTask? { tasks.first { $0.id == id } }
    private func title(for id: UUID) -> String { task(id)?.title ?? "" }

    private func color(for id: UUID) -> Color {
        guard let colID = task(id)?.columnID,
              let order = columns.first(where: { $0.id == colID })?.order
        else { return Theme.textTertiary }
        return Theme.columnColor(order: order)
    }

    private func openEditor(_ id: UUID) {
        guard let t = task(id) else { return }
        NotificationCenter.default.post(name: .openTaskEditor, object: TaskEditorView.Mode.edit(t))
    }

    // MARK: 拖拽提交

    private func commitMove(_ row: GanttRow, g: GanttGeometry, translationX: CGFloat) {
        let days = g.daysDelta(translationX: translationX)
        guard days != 0 else { return }
        let r = g.shifted(start: row.start, end: row.end, byDays: days)
        write(row.id, start: r.start, end: r.end)
    }

    private func commitResizeLeft(_ row: GanttRow, g: GanttGeometry, translationX: CGFloat) {
        guard let start = row.start ?? row.end else { return }
        let days = g.daysDelta(translationX: translationX)
        guard days != 0 else { return }
        write(row.id, start: g.resizedStart(start: start, end: row.end, byDays: days), end: row.end)
    }

    private func commitResizeRight(_ row: GanttRow, g: GanttGeometry, translationX: CGFloat) {
        guard let end = row.end ?? row.start else { return }
        let days = g.daysDelta(translationX: translationX)
        guard days != 0 else { return }
        write(row.id, start: row.start, end: g.resizedEnd(start: row.start, end: end, byDays: days))
    }

    private func write(_ id: UUID, start: Date?, end: Date?) {
        guard let t = task(id) else { return }
        let deadlineChanged = t.deadline != end
        t.startDate = start
        t.deadline = end
        try? context.saveTracking()      // 自动打点 modifiedAt
        if deadlineChanged {
            scheduler.cancel(for: t)
            Task { await scheduler.schedule(for: t) }
        }
    }
}

/// 单根任务条:拖条身平移、拖左右端点改时长。落点经回调换算成日期。
private struct GanttBar: View {
    let title: String
    let color: Color
    let baseX: CGFloat
    let baseWidth: CGFloat
    let dayWidth: CGFloat
    let height: CGFloat
    let onMove: (CGFloat) -> Void
    let onResizeLeft: (CGFloat) -> Void
    let onResizeRight: (CGFloat) -> Void
    let onTap: () -> Void

    @State private var moveDX: CGFloat = 0
    @State private var leftDX: CGFloat = 0
    @State private var rightDX: CGFloat = 0

    private let handleW: CGFloat = 8

    var body: some View {
        let x = baseX + moveDX + leftDX
        let w = max(dayWidth, baseWidth - leftDX + rightDX)
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color.opacity(0.85))
            .frame(width: w, height: height - 6)
            .overlay(alignment: .leading) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .overlay(alignment: .leading) { handle(.left) }
            .overlay(alignment: .trailing) { handle(.right) }
            .offset(x: x, y: 3)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { moveDX = $0.translation.width }
                    .onEnded { v in onMove(v.translation.width); moveDX = 0 }
            )
            .onTapGesture { onTap() }
    }

    private enum Edge { case left, right }

    private func handle(_ edge: Edge) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))   // 命中区域,几乎透明
            .frame(width: handleW, height: height - 6)
            .overlay {
                Capsule().fill(Color.white.opacity(0.55)).frame(width: 2, height: (height - 6) * 0.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if edge == .left { leftDX = v.translation.width }
                        else { rightDX = v.translation.width }
                    }
                    .onEnded { v in
                        if edge == .left { onResizeLeft(v.translation.width); leftDX = 0 }
                        else { onResizeRight(v.translation.width); rightDX = 0 }
                    }
            )
    }
}
```

- [ ] **Step 2: 构建验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -30`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 手测核对**

启动 App,切到"甘特" tab,核对:
- 有起止的任务画出从 start 到 deadline 的横条,颜色随所属看板列;
- 只有 deadline 的任务画出当天单格短条;
- 无起止的任务出现在底部"未排期"区;
- 拖条身整体平移、拖左/右端点改时长,落点按整天吸附,松手后条停在新位置;
- 改 deadline 的任务,提醒被重排(不报错);
- 横向滚动时日期头与条同步移动,左侧任务名列与顶部日期保持冻结;
- 点击任务名 / 条 / 未排期项都能打开编辑器。

- [ ] **Step 4: 回归 —— 跑一遍受影响的纯逻辑套件**

Run(逐套件):
```
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/GanttGeometryTests 2>&1 | tail -20
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncDocumentTests 2>&1 | tail -20
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -20
```
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/Board/GanttLensView.swift
git commit -m "feat(gantt): implement draggable/resizable gantt lens"
```

---

## 自查清单(写计划后复核,已通过)

- **Spec 覆盖**:
  - startDate 语义/分钟粒度 → Task 1(模型)、Task 4(编辑器,复用 NoirDatePicker)。
  - 同步 → Task 2。MCP → Task 3。
  - 甘特 tab/图标/不分组按 startDate 排序 → Task 7 + Task 8(`partition`)。
  - 按列着色 → Task 5 + Task 8(`color(for:)`)。
  - 按天/两周/可滑 → Task 8(`dayW = 视口/14` + 横向 ScrollView)。
  - 拖动+拉伸端点(DragGesture)→ Task 8(`GanttBar`)+ Task 6(换算)。
  - 缺时间:只有 deadline→单格、皆无→未排期区 → Task 6(`barFrame`)+ Task 8(`unscheduledSection`)。
  - 防御 start>end → Task 6(`barFrame`)。
  - 测试策略:几何/排序单测 Task 6;同步往返 Task 2;MCP Task 3;拖拽仅手测(XCUITest 不可驱动)→ 符合。
- **占位符**:无 TBD/TODO;每段含完整代码与命令。
- **类型一致性**:`GanttRow`/`GanttGeometry`/`partition`/`columnColor(order:)`/`barFrame`/`shifted`/`resizedStart`/`resizedEnd` 在 Task 6 定义,Task 8 按同名同签名调用;`.openTaskEditor` 通知与 `TaskEditorView.Mode.edit` 与 `LensCard` 现有用法一致。
- **已知取舍**:已记录于 spec —— 冻结行列靠 `onScrollGeometryChange`(macOS 26.5 可用);"未排期拖上时间轴"为后续增强,v1 用点击编辑。
