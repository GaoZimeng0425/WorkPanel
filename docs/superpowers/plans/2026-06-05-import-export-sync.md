# Import / Export (跨机器同步) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 WorkPanel 能把全部任务/看板列/日计划/设置导出为单个 JSON 文件,并在另一台机器按 ID 合并导入(最新者胜),实现手动跨机器同步。

**Architecture:** 给三个 `@Model`(`TodoTask`/`BoardColumn`/`DayPlan`)加 `modifiedAt`,通过 `Timestamped` 协议 + 单一 `ModelContext.saveTracking()` 助手在保存时打点;把现有 `context.save()` 调用迁移到 `saveTracking()`。新增 `Sync/` 模块:全保真 Codable DTO、导出/解析/合并服务。设置面板「通用」tab 加一张「数据同步」卡片驱动文件面板与导入确认弹窗。导入合并刻意用普通 `save()` 以保留文件时间戳。

**Tech Stack:** Swift / SwiftUI / SwiftData / AppKit(NSSavePanel/NSOpenPanel)/ Swift Testing。

**测试运行约定:** 整包 `xcodebuild test` 可能拖死 testmanagerd;务必按 suite 运行:
```bash
xcodebuild test -scheme WorkPanel \
  -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/<SuiteName>
```

**新文件位置:** `WorkPanel/Sync/` 与 `WorkPanelTests/` 下的文件由 filesystem-synced group 自动纳入,**不要**编辑 `project.pbxproj`。

---

## Task 1: `modifiedAt` 字段 + `Timestamped` 协议

**Files:**
- Create: `WorkPanel/Sync/Timestamped.swift`
- Modify: `WorkPanel/Models/TodoTask.swift`
- Modify: `WorkPanel/Models/BoardColumn.swift`
- Modify: `WorkPanel/Models/DayPlan.swift`
- Test: `WorkPanelTests/TimestampedTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/TimestampedTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct TimestampedTests {
    @Test func threeModelsConformAndModifiedAtIsSettable() {
        let epoch = Date(timeIntervalSince1970: 0)
        let models: [any Timestamped] = [
            TodoTask(title: "a"),
            BoardColumn(name: "c", order: 0),
            DayPlan(day: .now),
        ]
        for m in models {
            m.modifiedAt = epoch
            #expect(m.modifiedAt == epoch)
        }
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TimestampedTests
```
Expected: 编译失败(`Timestamped` 未定义 / 模型无 `modifiedAt`)。

- [ ] **Step 3: 建协议文件**

`WorkPanel/Sync/Timestamped.swift`:

```swift
import Foundation
import SwiftData

/// 带「最后修改时间」的模型。用于导入合并的最新者胜判定,以及 saveTracking 打点。
protocol Timestamped: AnyObject {
    var modifiedAt: Date { get set }
}
```

- [ ] **Step 4: 给三个模型加 `modifiedAt` 并 conform**

`WorkPanel/Models/TodoTask.swift` —— 在 `var urgencyOverride: Bool?` 之后加一行属性:

```swift
    var modifiedAt: Date = .now      // 跨机器同步的最新者胜判定
```

把类声明改为 conform(第 5 行):

```swift
final class TodoTask: Timestamped {
```

`WorkPanel/Models/BoardColumn.swift` —— 在 `var order: Int` 后加属性,并 conform:

```swift
@Model
final class BoardColumn: Timestamped {
    var id: UUID
    var name: String
    var order: Int
    var modifiedAt: Date = .now

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
    }
}
```

`WorkPanel/Models/DayPlan.swift` —— 同样:

```swift
@Model
final class DayPlan: Timestamped {
    var day: Date
    var committedTaskIDs: [UUID]
    var modifiedAt: Date = .now

    init(day: Date, committedTaskIDs: [UUID] = []) {
        self.day = day
        self.committedTaskIDs = committedTaskIDs
    }
}
```

> 注:`modifiedAt` 带默认值 `= .now`,SwiftData 走轻量迁移,旧库已有行升级时获得默认值,首次导出会被正常打点。`TodoTask` 的 `init` 无需显式赋值(属性默认值已覆盖)。

- [ ] **Step 5: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TimestampedTests
```
Expected: PASS。

- [ ] **Step 6: 回归现有 store 测试(确认迁移未破坏)**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests
```
Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add WorkPanel/Sync/Timestamped.swift WorkPanel/Models/TodoTask.swift WorkPanel/Models/BoardColumn.swift WorkPanel/Models/DayPlan.swift WorkPanelTests/TimestampedTests.swift
git commit -m "feat(model): add modifiedAt + Timestamped to TodoTask/BoardColumn/DayPlan"
```

---

## Task 2: `ModelContext.saveTracking()` 打点助手

**Files:**
- Modify: `WorkPanel/Sync/Timestamped.swift`
- Test: `WorkPanelTests/SaveTrackingTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/SaveTrackingTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct SaveTrackingTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    @Test func saveTrackingStampsInsertedModels() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "T")
        ctx.insert(task)
        task.modifiedAt = Date(timeIntervalSince1970: 0)
        let stamp = Date(timeIntervalSince1970: 1000)
        try ctx.saveTracking(now: stamp)
        #expect(task.modifiedAt == stamp)
    }

    @Test func saveTrackingStampsChangedModels() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "T")
        ctx.insert(task)
        task.modifiedAt = Date(timeIntervalSince1970: 0)
        try ctx.save()                       // 先落库,清空 inserted 集
        task.title = "改了"                   // 触发 changed
        let stamp = Date(timeIntervalSince1970: 2000)
        try ctx.saveTracking(now: stamp)
        #expect(task.modifiedAt == stamp)
    }

    @Test func plainSaveDoesNotStamp() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "T")
        ctx.insert(task)
        let early = Date(timeIntervalSince1970: 0)
        task.modifiedAt = early
        try ctx.save()
        #expect(task.modifiedAt == early)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SaveTrackingTests
```
Expected: 编译失败(`saveTracking` 未定义)。

- [ ] **Step 3: 实现助手**

在 `WorkPanel/Sync/Timestamped.swift` 末尾追加:

```swift
extension ModelContext {
    /// 保存前把所有「新插入 + 被修改」且符合 Timestamped 的模型的 modifiedAt 打成 now,然后保存。
    /// 导入合并路径刻意用普通 save() 以保留文件里的时间戳,故不要在那里用本方法。
    func saveTracking(now: Date = .now) throws {
        for model in insertedModelsArray + changedModelsArray {
            (model as? Timestamped)?.modifiedAt = now
        }
        try save()
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SaveTrackingTests
```
Expected: PASS(3 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/Timestamped.swift WorkPanelTests/SaveTrackingTests.swift
git commit -m "feat(sync): ModelContext.saveTracking stamps modifiedAt before save"
```

---

## Task 3: 迁移现有 `context.save()` 调用点到 `saveTracking()`

**Files (modify):** `WorkPanel/WorkPanelApp.swift`、`WorkPanel/UI/TaskEditorView.swift`、`WorkPanel/UI/TaskListView.swift`、`WorkPanel/UI/BoardView.swift`、`WorkPanel/UI/KanbanLensView.swift`、`WorkPanel/UI/PriorityLensView.swift`、`WorkPanel/UI/LensCard.swift`、`WorkPanel/UI/PlanningView.swift`、`WorkPanel/UI/TodayLensView.swift`、`WorkPanel/MCP/MCPToolHandlers.swift`

- [ ] **Step 1: 全局替换(仅 app 源码目录,不含测试)**

Run:
```bash
grep -rl 'context.save()' WorkPanel | xargs sed -i '' 's/context\.save()/context.saveTracking()/g'
```
说明:`WorkPanel` 指 app 源码目录;`WorkPanelTests/` 是同级目录,不受影响(其中的 `store.context.save()` 保持原样)。`try? context.save()` → `try? context.saveTracking()`,`try context.save()` → `try context.saveTracking()`,二者签名一致(均 `throws`)。

- [ ] **Step 2: 核对替换数量**

Run:
```bash
grep -rn 'context.saveTracking()' WorkPanel | wc -l
grep -rn 'context.save()' WorkPanel
```
Expected: 第一条约 27(WorkPanelApp 1、TaskEditorView 2、TaskListView 4、BoardView 1、KanbanLensView 5、PriorityLensView 1、LensCard 2、PlanningView 3、TodayLensView 1、MCPToolHandlers 7);第二条 **无输出**(app 目录内已无裸 `context.save()`)。

- [ ] **Step 3: 编译并跑回归测试**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardStoreTests
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoStoreTests
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests
```
Expected: 全部 PASS。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel
git commit -m "refactor(sync): route app save() calls through saveTracking()"
```

---

## Task 4: 设置序列化 `SyncSettingsDTO` + 读/写

**Files:**
- Create: `WorkPanel/Sync/SyncSettings.swift`
- Test: `WorkPanelTests/SyncSettingsTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/SyncSettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncSettingsTests {
    /// 用独立 suiteName 的 UserDefaults,避免污染真实偏好。
    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "SyncSettingsTests")!
        for k in d.dictionaryRepresentation().keys { d.removeObject(forKey: k) }
        return d
    }

    @Test func snapshotReadsWhitelistedKeys() {
        let d = makeDefaults()
        d.set(15, forKey: AppSettings.Key.reminderLeadMinutes)
        d.set("dark", forKey: AppSettings.Key.appearance)
        d.set("sk-secret", forKey: AppSettings.Key.aiAPIKey)
        let dto = SyncSettings.snapshot(from: d)
        #expect(dto.reminderLeadMinutes == 15)
        #expect(dto.appearance == "dark")
        #expect(dto.aiAPIKey == "sk-secret")
        #expect(dto.mcpPort == nil)          // 未设置 → nil
    }

    @Test func applyWritesOnlyNonNilKeys() {
        let d = makeDefaults()
        d.set(99, forKey: AppSettings.Key.mcpPort)
        var dto = SyncSettingsDTO()
        dto.appearance = "light"             // 仅这一项有值
        SyncSettings.apply(dto, to: d)
        #expect(d.string(forKey: AppSettings.Key.appearance) == "light")
        #expect(d.integer(forKey: AppSettings.Key.mcpPort) == 99)   // 未被 nil 覆盖
    }

    @Test func excludesLastPlannedDay() {
        let d = makeDefaults()
        d.set(123.0, forKey: AppSettings.Key.lastPlannedDay)
        let dto = SyncSettings.snapshot(from: d)
        // DTO 无该字段;apply 也不会触碰它
        var fresh = SyncSettingsDTO()
        fresh.mcpPort = 1
        SyncSettings.apply(fresh, to: d)
        #expect(d.double(forKey: AppSettings.Key.lastPlannedDay) == 123.0)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncSettingsTests
```
Expected: 编译失败(`SyncSettings` / `SyncSettingsDTO` 未定义)。

- [ ] **Step 3: 实现**

`WorkPanel/Sync/SyncSettings.swift`:

```swift
import Foundation

/// 同步文件里的设置部分。白名单内的键全部 Optional —— 缺键即 nil,apply 时跳过。
/// 刻意不含 lastPlannedDay(本机当日规划状态,不应跨机器覆盖)。
struct SyncSettingsDTO: Codable {
    var reminderLeadMinutes: Int?
    var appearance: String?
    var notificationSound: Bool?
    var defaultPriority: Int?
    var boardViewMode: String?
    var mcpEnabled: Bool?
    var mcpPort: Int?
    var mcpToken: String?
    var boardHeight: Double?
    var aiBaseURL: String?
    var aiModel: String?
    var aiAPIKey: String?
    var aiPrompts: String?        // UserDefaults 里本就是 JSON 字符串,原样搬运
}

enum SyncSettings {
    static func snapshot(from d: UserDefaults = .standard) -> SyncSettingsDTO {
        var dto = SyncSettingsDTO()
        let K = AppSettings.Key.self
        dto.reminderLeadMinutes = d.object(forKey: K.reminderLeadMinutes) as? Int
        dto.appearance          = d.string(forKey: K.appearance)
        dto.notificationSound   = d.object(forKey: K.notificationSound) as? Bool
        dto.defaultPriority     = d.object(forKey: K.defaultPriority) as? Int
        dto.boardViewMode       = d.string(forKey: K.boardViewMode)
        dto.mcpEnabled          = d.object(forKey: K.mcpEnabled) as? Bool
        dto.mcpPort             = d.object(forKey: K.mcpPort) as? Int
        dto.mcpToken            = d.string(forKey: K.mcpToken)
        dto.boardHeight         = d.object(forKey: K.boardHeight) as? Double
        dto.aiBaseURL           = d.string(forKey: K.aiBaseURL)
        dto.aiModel             = d.string(forKey: K.aiModel)
        dto.aiAPIKey            = d.string(forKey: K.aiAPIKey)
        dto.aiPrompts           = d.string(forKey: K.aiPrompts)
        return dto
    }

    static func apply(_ dto: SyncSettingsDTO, to d: UserDefaults = .standard) {
        let K = AppSettings.Key.self
        if let v = dto.reminderLeadMinutes { d.set(v, forKey: K.reminderLeadMinutes) }
        if let v = dto.appearance          { d.set(v, forKey: K.appearance) }
        if let v = dto.notificationSound   { d.set(v, forKey: K.notificationSound) }
        if let v = dto.defaultPriority     { d.set(v, forKey: K.defaultPriority) }
        if let v = dto.boardViewMode       { d.set(v, forKey: K.boardViewMode) }
        if let v = dto.mcpEnabled          { d.set(v, forKey: K.mcpEnabled) }
        if let v = dto.mcpPort             { d.set(v, forKey: K.mcpPort) }
        if let v = dto.mcpToken            { d.set(v, forKey: K.mcpToken) }
        if let v = dto.boardHeight         { d.set(v, forKey: K.boardHeight) }
        if let v = dto.aiBaseURL           { d.set(v, forKey: K.aiBaseURL) }
        if let v = dto.aiModel             { d.set(v, forKey: K.aiModel) }
        if let v = dto.aiAPIKey            { d.set(v, forKey: K.aiAPIKey) }
        if let v = dto.aiPrompts           { d.set(v, forKey: K.aiPrompts) }
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncSettingsTests
```
Expected: PASS(3 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/SyncSettings.swift WorkPanelTests/SyncSettingsTests.swift
git commit -m "feat(sync): SyncSettings snapshot/apply over whitelisted prefs"
```

---

## Task 5: `SyncDocument` 全保真 DTO

**Files:**
- Create: `WorkPanel/Sync/SyncDocument.swift`
- Test: `WorkPanelTests/SyncDocumentTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/SyncDocumentTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncDocumentTests {
    @Test func taskDTORoundTripsAllFields() throws {
        let t = TodoTask(title: "标题", notes: "备注", priority: .high,
                         tags: ["x", "y"], recurrence: .weekly)
        t.deadline = Date(timeIntervalSince1970: 100)
        t.isCompleted = true
        t.completedAt = Date(timeIntervalSince1970: 200)
        t.snoozedUntil = Date(timeIntervalSince1970: 300)
        t.columnID = UUID()
        t.boardOrder = 5
        t.planOrder = 7
        t.urgencyOverride = true
        t.modifiedAt = Date(timeIntervalSince1970: 400)

        let dto = SyncTaskDTO(t)
        let data = try SyncDocument.encoder.encode(dto)
        let back = try SyncDocument.decoder.decode(SyncTaskDTO.self, from: data)

        #expect(back.id == t.id)
        #expect(back.title == "标题")
        #expect(back.recurrenceRaw == "weekly")
        #expect(back.priorityRaw == Priority.high.rawValue)
        #expect(back.deadline == Date(timeIntervalSince1970: 100))
        #expect(back.completedAt == Date(timeIntervalSince1970: 200))
        #expect(back.snoozedUntil == Date(timeIntervalSince1970: 300))
        #expect(back.columnID == t.columnID)
        #expect(back.boardOrder == 5)
        #expect(back.planOrder == 7)
        #expect(back.urgencyOverride == true)
        #expect(back.modifiedAt == Date(timeIntervalSince1970: 400))
    }

    @Test func nilOptionalsRoundTrip() throws {
        let t = TodoTask(title: "空可选")     // deadline/completedAt/... 全 nil
        let dto = SyncTaskDTO(t)
        let data = try SyncDocument.encoder.encode(dto)
        let back = try SyncDocument.decoder.decode(SyncTaskDTO.self, from: data)
        #expect(back.deadline == nil)
        #expect(back.completedAt == nil)
        #expect(back.recurrenceRaw == nil)
        #expect(back.urgencyOverride == nil)
        #expect(back.columnID == nil)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncDocumentTests
```
Expected: 编译失败(`SyncTaskDTO` / `SyncDocument` 未定义)。

- [ ] **Step 3: 实现 DTO 与文档**

`WorkPanel/Sync/SyncDocument.swift`:

```swift
import Foundation

struct SyncTaskDTO: Codable {
    var id: UUID
    var title: String
    var notes: String
    var deadline: Date?
    var priorityRaw: Int
    var tags: [String]
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var snoozedUntil: Date?
    var recurrenceRaw: String?
    var columnID: UUID?
    var boardOrder: Int
    var planOrder: Int
    var urgencyOverride: Bool?
    var modifiedAt: Date

    init(_ t: TodoTask) {
        id = t.id; title = t.title; notes = t.notes; deadline = t.deadline
        priorityRaw = t.priorityRaw; tags = t.tags; isCompleted = t.isCompleted
        completedAt = t.completedAt; createdAt = t.createdAt; snoozedUntil = t.snoozedUntil
        recurrenceRaw = t.recurrenceRaw; columnID = t.columnID; boardOrder = t.boardOrder
        planOrder = t.planOrder; urgencyOverride = t.urgencyOverride; modifiedAt = t.modifiedAt
    }

    func makeModel() -> TodoTask { let t = TodoTask(title: title); apply(to: t); return t }

    func apply(to t: TodoTask) {
        t.id = id; t.title = title; t.notes = notes; t.deadline = deadline
        t.priorityRaw = priorityRaw; t.tags = tags; t.isCompleted = isCompleted
        t.completedAt = completedAt; t.createdAt = createdAt; t.snoozedUntil = snoozedUntil
        t.recurrenceRaw = recurrenceRaw; t.columnID = columnID; t.boardOrder = boardOrder
        t.planOrder = planOrder; t.urgencyOverride = urgencyOverride; t.modifiedAt = modifiedAt
    }
}

struct SyncColumnDTO: Codable {
    var id: UUID
    var name: String
    var order: Int
    var modifiedAt: Date

    init(_ c: BoardColumn) { id = c.id; name = c.name; order = c.order; modifiedAt = c.modifiedAt }

    func makeModel() -> BoardColumn { let c = BoardColumn(name: name, order: order); apply(to: c); return c }
    func apply(to c: BoardColumn) { c.id = id; c.name = name; c.order = order; c.modifiedAt = modifiedAt }
}

struct SyncDayPlanDTO: Codable {
    var day: Date
    var committedTaskIDs: [UUID]
    var modifiedAt: Date

    init(_ p: DayPlan) { day = p.day; committedTaskIDs = p.committedTaskIDs; modifiedAt = p.modifiedAt }

    func makeModel() -> DayPlan {
        let p = DayPlan(day: day, committedTaskIDs: committedTaskIDs); p.modifiedAt = modifiedAt; return p
    }
}

struct SyncDocument: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var tasks: [SyncTaskDTO]
    var columns: [SyncColumnDTO]
    var dayPlans: [SyncDayPlanDTO]
    var settings: SyncSettingsDTO

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncDocumentTests
```
Expected: PASS(2 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/SyncDocument.swift WorkPanelTests/SyncDocumentTests.swift
git commit -m "feat(sync): full-fidelity SyncDocument + DTOs (iso8601 codable)"
```

---

## Task 6: `SyncService.exportData` 与 `parse`

**Files:**
- Create: `WorkPanel/Sync/SyncService.swift`
- Test: `WorkPanelTests/SyncServiceExportTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/SyncServiceExportTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct SyncServiceExportTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    @Test func exportThenParseReproducesCounts() throws {
        let ctx = try makeContext()
        ctx.insert(BoardColumn(name: "计划中", order: 0))
        ctx.insert(TodoTask(title: "A"))
        ctx.insert(TodoTask(title: "B"))
        ctx.insert(DayPlan(day: Date(timeIntervalSince1970: 0)))
        try ctx.save()

        let data = try SyncService.exportData(context: ctx, now: Date(timeIntervalSince1970: 999))
        let doc = try SyncService.parse(data)

        #expect(doc.schemaVersion == SyncDocument.currentSchemaVersion)
        #expect(doc.exportedAt == Date(timeIntervalSince1970: 999))
        #expect(doc.columns.count == 1)
        #expect(doc.tasks.count == 2)
        #expect(doc.dayPlans.count == 1)
    }

    @Test func parseRejectsUnknownSchemaVersion() throws {
        let json = #"{"schemaVersion":999,"exportedAt":"2026-01-01T00:00:00Z","tasks":[],"columns":[],"dayPlans":[],"settings":{}}"#
        #expect(throws: SyncError.self) {
            try SyncService.parse(Data(json.utf8))
        }
    }

    @Test func parseRejectsCorruptData() {
        #expect(throws: (any Error).self) {
            try SyncService.parse(Data("not json".utf8))
        }
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceExportTests
```
Expected: 编译失败(`SyncService` / `SyncError` 未定义)。

- [ ] **Step 3: 实现 export + parse**

`WorkPanel/Sync/SyncService.swift`:

```swift
import Foundation
import SwiftData

enum SyncError: Error {
    case unsupportedVersion(Int)
}

@MainActor
enum SyncService {
    static func exportData(context: ModelContext, now: Date = .now) throws -> Data {
        let tasks   = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        let columns = (try? context.fetch(FetchDescriptor<BoardColumn>())) ?? []
        let plans   = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        let doc = SyncDocument(
            schemaVersion: SyncDocument.currentSchemaVersion,
            exportedAt: now,
            tasks: tasks.map(SyncTaskDTO.init),
            columns: columns.map(SyncColumnDTO.init),
            dayPlans: plans.map(SyncDayPlanDTO.init),
            settings: SyncSettings.snapshot()
        )
        return try SyncDocument.encoder.encode(doc)
    }

    static func parse(_ data: Data) throws -> SyncDocument {
        let doc = try SyncDocument.decoder.decode(SyncDocument.self, from: data)
        guard doc.schemaVersion == SyncDocument.currentSchemaVersion else {
            throw SyncError.unsupportedVersion(doc.schemaVersion)
        }
        return doc
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceExportTests
```
Expected: PASS(3 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/SyncService.swift WorkPanelTests/SyncServiceExportTests.swift
git commit -m "feat(sync): SyncService export + parse with schema-version guard"
```

---

## Task 7: `SyncService.merge`(按 ID 合并,最新者胜)

**Files:**
- Modify: `WorkPanel/Sync/SyncService.swift`
- Test: `WorkPanelTests/SyncServiceMergeTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/SyncServiceMergeTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct SyncServiceMergeTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    private func docWith(tasks: [SyncTaskDTO] = [], columns: [SyncColumnDTO] = [],
                         dayPlans: [SyncDayPlanDTO] = [],
                         settings: SyncSettingsDTO = SyncSettingsDTO()) -> SyncDocument {
        SyncDocument(schemaVersion: 1, exportedAt: .now,
                     tasks: tasks, columns: columns, dayPlans: dayPlans, settings: settings)
    }

    @Test func insertsTaskNotPresentLocally() throws {
        let ctx = try makeContext()
        let incoming = TodoTask(title: "新")
        incoming.modifiedAt = Date(timeIntervalSince1970: 10)
        let report = SyncService.merge(docWith(tasks: [SyncTaskDTO(incoming)]),
                                       into: ctx, includeSettings: false)
        let all = try ctx.fetch(FetchDescriptor<TodoTask>())
        #expect(all.count == 1)
        #expect(all.first?.title == "新")
        #expect(report.tasksInserted == 1)
        #expect(report.tasksUpdated == 0)
    }

    @Test func newerIncomingOverwritesLocal() throws {
        let ctx = try makeContext()
        let local = TodoTask(title: "旧标题")
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local)
        try ctx.save()

        var dto = SyncTaskDTO(local)
        dto.title = "新标题"
        dto.modifiedAt = Date(timeIntervalSince1970: 20)   // 更新

        let report = SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(local.title == "新标题")
        #expect(report.tasksUpdated == 1)
        #expect(report.tasksInserted == 0)
    }

    @Test func olderIncomingIsSkipped() throws {
        let ctx = try makeContext()
        let local = TodoTask(title: "本地新")
        local.modifiedAt = Date(timeIntervalSince1970: 30)
        ctx.insert(local)
        try ctx.save()

        var dto = SyncTaskDTO(local)
        dto.title = "文件旧"
        dto.modifiedAt = Date(timeIntervalSince1970: 5)    // 更旧

        let report = SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(local.title == "本地新")
        #expect(report.tasksUpdated == 0)
    }

    @Test func equalTimestampIsSkipped() throws {
        let ctx = try makeContext()
        let local = TodoTask(title: "本地")
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local)
        try ctx.save()

        var dto = SyncTaskDTO(local)
        dto.title = "文件"
        dto.modifiedAt = Date(timeIntervalSince1970: 10)   // 相等
        let report = SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(local.title == "本地")
        #expect(report.tasksUpdated == 0)
    }

    @Test func dayPlanMatchedByDayNotInstant() throws {
        let ctx = try makeContext()
        let cal = Calendar(identifier: .gregorian)
        let morning = cal.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let local = DayPlan(day: morning, committedTaskIDs: [])
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local)
        try ctx.save()

        let evening = morning.addingTimeInterval(20 * 3600)   // 同一天稍晚
        let newID = UUID()
        var dto = SyncDayPlanDTO(DayPlan(day: evening, committedTaskIDs: [newID]))
        dto.modifiedAt = Date(timeIntervalSince1970: 20)

        let report = SyncService.merge(docWith(dayPlans: [dto]),
                                       into: ctx, includeSettings: false, calendar: cal)
        let all = try ctx.fetch(FetchDescriptor<DayPlan>())
        #expect(all.count == 1)                       // 没有新建,合到同一天
        #expect(all.first?.committedTaskIDs == [newID])
        #expect(report.dayPlansUpdated == 1)
    }

    @Test func settingsAppliedOnlyWhenRequested() throws {
        let ctx = try makeContext()
        var settings = SyncSettingsDTO()
        settings.aiModel = "gpt-x"
        // includeSettings: false → 不应用
        let r1 = SyncService.merge(docWith(settings: settings), into: ctx, includeSettings: false)
        #expect(r1.settingsApplied == false)
        // includeSettings: true → settingsApplied 为真
        let r2 = SyncService.merge(docWith(settings: settings), into: ctx, includeSettings: true)
        #expect(r2.settingsApplied == true)
    }
}
```

> 注:`settingsAppliedOnlyWhenRequested` 只校验 `settingsApplied` 标志。`includeSettings: true` 时 `merge` 会经 `SyncSettings.apply` 向 `UserDefaults.standard` 写入 `aiModel="gpt-x"`(测试宿主内,无害;键值写入正确性已由 Task 4 的 `SyncSettingsTests` 用独立 suite 覆盖)。

- [ ] **Step 2: 运行确认失败**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceMergeTests
```
Expected: 编译失败(`merge` / `SyncReport` 未定义)。

- [ ] **Step 3: 实现 SyncReport + merge**

在 `WorkPanel/Sync/SyncService.swift` 中,`SyncError` 之后加 `SyncReport`:

```swift
struct SyncReport {
    var tasksInserted = 0
    var tasksUpdated = 0
    var columnsInserted = 0
    var columnsUpdated = 0
    var dayPlansInserted = 0
    var dayPlansUpdated = 0
    var settingsApplied = false

    var totalInserted: Int { tasksInserted + columnsInserted + dayPlansInserted }
    var totalUpdated: Int { tasksUpdated + columnsUpdated + dayPlansUpdated }
}
```

在 `SyncService` 内加 `merge`(放在 `parse` 之后):

```swift
    /// 按 ID 合并(DayPlan 按归一化 day),最新者胜。刻意用普通 save() 以保留文件时间戳。
    @discardableResult
    static func merge(_ doc: SyncDocument, into context: ModelContext,
                      includeSettings: Bool, calendar: Calendar = .current) -> SyncReport {
        var report = SyncReport()

        // 列(先于任务,使 columnID 引用可解析)
        let cols = (try? context.fetch(FetchDescriptor<BoardColumn>())) ?? []
        var colByID = Dictionary(uniqueKeysWithValues: cols.map { ($0.id, $0) })
        for dto in doc.columns {
            if let local = colByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.columnsUpdated += 1 }
            } else {
                let c = dto.makeModel(); context.insert(c); colByID[dto.id] = c; report.columnsInserted += 1
            }
        }

        // 任务
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        var taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for dto in doc.tasks {
            if let local = taskByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.tasksUpdated += 1 }
            } else {
                let t = dto.makeModel(); context.insert(t); taskByID[dto.id] = t; report.tasksInserted += 1
            }
        }

        // 日计划(按 day 匹配)
        var plans = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        for dto in doc.dayPlans {
            let day = calendar.startOfDay(for: dto.day)
            if let local = plans.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                if dto.modifiedAt > local.modifiedAt {
                    local.committedTaskIDs = dto.committedTaskIDs
                    local.modifiedAt = dto.modifiedAt
                    report.dayPlansUpdated += 1
                }
            } else {
                let p = dto.makeModel(); context.insert(p); plans.append(p); report.dayPlansInserted += 1
            }
        }

        if includeSettings { SyncSettings.apply(doc.settings); report.settingsApplied = true }

        try? context.save()      // 普通 save:保留文件时间戳,不重新打点
        return report
    }
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceMergeTests
```
Expected: PASS(7 个用例)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/SyncService.swift WorkPanelTests/SyncServiceMergeTests.swift
git commit -m "feat(sync): SyncService.merge by id, newest-wins + SyncReport"
```

---

## Task 8: 设置面板「数据同步」卡片 + 导出/导入 UI

**Files:**
- Modify: `WorkPanel/UI/SettingsView.swift`

> 说明:UI 的拖拽/面板交互无法用 XCUITest 可靠驱动(见项目记忆),本任务靠手动验证。核心逻辑已由 Task 4–7 单测覆盖。SettingsView 在独立面板里展示、未注入 `modelContainer`,因此导出/导入直接用 `SharedModel.container.mainContext`。

- [ ] **Step 1: 加 import 与状态**

在 `WorkPanel/UI/SettingsView.swift` 顶部 import 区加:

```swift
import UniformTypeIdentifiers
```

在 `SettingsView` 的 `@State` 区(`@State private var mcpToken` 附近)加:

```swift
    @State private var pendingImport: PendingImport?
    @State private var importIncludesSettings = false

    /// .sheet(item:) 需要 Identifiable 包装。
    private struct PendingImport: Identifiable {
        let id = UUID()
        let doc: SyncDocument
    }
```

- [ ] **Step 2: 加导出/导入处理函数**

在 `SettingsView` 内(`copy(_:notice:)` 方法附近)加:

```swift
    private var exportFileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "WorkPanel-备份-\(f.string(from: Date())).json"
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = exportFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try SyncService.exportData(context: SharedModel.container.mainContext)
            try data.write(to: url)
            Notice.show("已导出")
        } catch {
            Notice.show("导出失败")
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let doc = try SyncService.parse(try Data(contentsOf: url))
            importIncludesSettings = false
            pendingImport = PendingImport(doc: doc)
        } catch {
            Notice.show("导入失败:文件格式无效")
        }
    }

    private func performImport(_ doc: SyncDocument) {
        let report = SyncService.merge(doc, into: SharedModel.container.mainContext,
                                       includeSettings: importIncludesSettings)
        if report.settingsApplied {
            AppSettings.appearance.apply()
            NotificationCenter.default.post(name: .mcpSettingsChanged, object: nil)
        }
        Notice.show("导入完成:新增 \(report.totalInserted),更新 \(report.totalUpdated)")
    }
```

- [ ] **Step 3: 加「数据同步」卡片**

在 `SettingsView` 内(`generalSection` 附近)加:

```swift
    private var dataSyncCard: some View {
        section("数据同步", systemImage: "arrow.triangle.2.circlepath") {
            row("导出到文件", systemImage: "square.and.arrow.up") {
                Button("导出…") { runExport() }
                    .buttonStyle(NoirPillButtonStyle())
            }
            divider
            row("从文件导入", systemImage: "square.and.arrow.down") {
                Button("导入…") { chooseImport() }
                    .buttonStyle(NoirPillButtonStyle())
            }
        }
    }
```

- [ ] **Step 4: 把卡片挂到「通用」tab,并挂导入确认 sheet**

把现有 `generalSection` 改为在原卡片下方追加 `dataSyncCard`。将其整体包进 VStack:

```swift
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("通用", systemImage: "slider.horizontal.3") {
                row("开机自启动", systemImage: "power") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do { try LaunchAtLogin.setEnabled(enabled) }
                            catch { launchAtLogin = LaunchAtLogin.isEnabled }
                        }
                }
                divider
                row("外观主题", systemImage: "circle.lefthalf.filled") {
                    Picker("", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: appearance) { _, raw in
                        (Appearance(rawValue: raw) ?? .system).apply()
                    }
                }
                divider
                row("新任务默认优先级", systemImage: "flag") {
                    Picker("", selection: $defaultPriority) {
                        ForEach(Priority.allCases.reversed(), id: \.rawValue) {
                            Text(Theme.priorityLabel($0)).tag($0.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            dataSyncCard
        }
    }
```

在 `body` 的最外层视图(`HStack(spacing: 0) { sidebar … rightPane }` 所在的那一层)末尾、`.onKeyPress(.escape)` 之前,加 sheet:

```swift
        .sheet(item: $pendingImport) { pending in
            importConfirmSheet(pending.doc)
        }
```

- [ ] **Step 5: 加导入确认 sheet 视图**

在 `SettingsView` 内加:

```swift
    private func importConfirmSheet(_ doc: SyncDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入预览")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("将合并 \(doc.tasks.count) 个任务 / \(doc.columns.count) 个看板列 / \(doc.dayPlans.count) 个日计划")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Toggle("同时导入设置(含 API Key 等密钥)", isOn: $importIncludesSettings)
                .toggleStyle(.switch)
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Spacer()
                Button("取消") { pendingImport = nil }
                    .buttonStyle(NoirPillButtonStyle())
                Button("导入") {
                    performImport(doc)
                    pendingImport = nil
                }
                .buttonStyle(NoirPillButtonStyle(prominent: true))
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
    }
```

- [ ] **Step 6: 编译**

Run:
```bash
xcodebuild build -scheme WorkPanel -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 7: 手动验证**

1. 启动 app,打开设置(⌘,)→「通用」→ 见「数据同步」卡片。
2. 点「导出…」→ 选位置保存 → 见「已导出」提示 → 文件存在且为合法 JSON(`schemaVersion:1`,含 tasks/columns/dayPlans/settings)。
3. 点「导入…」→ 选刚导出的文件 → 弹「导入预览」,数量正确 → 不勾设置 → 点「导入」→ 见「导入完成」提示,数据无重复(同 ID 不新增)。
4. 选一个损坏文件(随便一个 .txt 改名 .json)→ 见「导入失败:文件格式无效」。

- [ ] **Step 8: 提交**

```bash
git add WorkPanel/UI/SettingsView.swift
git commit -m "feat(settings): 数据同步 card — export/import with merge preview"
```

---

## 完成标准

- 所有新测试套件 PASS:`TimestampedTests`、`SaveTrackingTests`、`SyncSettingsTests`、`SyncDocumentTests`、`SyncServiceExportTests`、`SyncServiceMergeTests`。
- 回归套件 PASS:`BoardStoreTests`、`TodoStoreTests`、`MCPToolHandlersTests`。
- app 编译通过,设置面板可导出/导入,手动验证 4 步全过。
- 导入对同 ID 记录按 `modifiedAt` 最新者胜;较旧/相等跳过;删除不传播(符合设计)。
