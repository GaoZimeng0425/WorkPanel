# 同步删除传播(墓碑机制)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `TodoTask` / `BoardColumn` 的删除能跨设备传播且不被对端复活,通过墓碑(Tombstone)机制。

**Architecture:** 删除时硬删原记录并插入一条 `Tombstone`(id + kind + deletedAt)。同步文档新增可选 `tombstones` 数组(`schemaVersion` 保持 1,向后兼容)。`SyncService.merge` 先应用传入墓碑(按时间戳删除本地记录),再在 task/column 合并时用墓碑抑制第三方文档的重新插入;对端编辑晚于删除则复活并撤销墓碑。

**Tech Stack:** Swift / SwiftData (`@Model`)、Swift Testing(`import Testing`、`@Test`)、Xcode `xcodebuild`。

**关联 spec:** `docs/superpowers/specs/2026-06-07-sync-deletion-tombstones-design.md`

**测试注意(项目已知坑):** 全包 `xcodebuild test` 可能卡死 testmanagerd;每个测试步骤都用 `-only-testing:` 跑单个 suite。构建用 `xcodebuild ... build`。所有命令的 destination 用 `'platform=macOS'`,scheme 用 `WorkPanel`。

---

## File Structure

**新建**
- `WorkPanel/Models/Tombstone.swift` — `Tombstone` `@Model` + `TombstoneKind` 枚举。单一职责:删除墓碑的领域模型。

**修改**
- `WorkPanel/WorkPanelApp.swift:19` — 把 `Tombstone.self` 加入 `Schema`。
- `WorkPanel/Store/TodoStore.swift:59-61` — `delete` 改为硬删 + 建 `.task` 墓碑。
- `WorkPanel/Store/BoardStore.swift:56-65` — `delete` 末尾建 `.column` 墓碑。
- `WorkPanel/UI/TaskEditorView.swift:381-387` — `deleteTask` 改走 `todoStore.delete`。
- `WorkPanel/UI/LensCard.swift:21-27` — 右键删除改走 `todoStore.delete`。
- `WorkPanel/Sync/SyncDocument.swift` — 新增 `SyncTombstoneDTO`;`SyncDocument` 加可选 `tombstones`。
- `WorkPanel/Sync/SyncService.swift` — `SyncReport` 加删除计数;`exportData` 带上墓碑;`merge` 加墓碑处理。

**测试修改/新增**
- `WorkPanelTests/TodoStoreTests.swift` — 容器加 `Tombstone.self`;新增删除建墓碑测试。
- `WorkPanelTests/BoardStoreTests.swift` — 容器加 `Tombstone.self`;新增列墓碑测试。
- `WorkPanelTests/SyncDocumentTests.swift` — 墓碑 DTO 往返 + 向后兼容。
- `WorkPanelTests/SyncServiceExportTests.swift` — 导出含墓碑。
- `WorkPanelTests/SyncServiceMergeTests.swift` — 容器/`docWith` 升级 + 6 个墓碑合并测试。

---

## Task 1: Tombstone 模型与 schema 注册

**Files:**
- Create: `WorkPanel/Models/Tombstone.swift`
- Modify: `WorkPanel/WorkPanelApp.swift:19`

- [ ] **Step 1: 创建模型文件**

`WorkPanel/Models/Tombstone.swift`:
```swift
import Foundation
import SwiftData

enum TombstoneKind: String, Codable { case task, column }

/// 删除墓碑:记录某条记录被删除的事实,用于跨设备传播删除、抑制对端复活。
/// 刻意不实现 Timestamped——它从不被编辑,merge 用普通 save() 不会重新打点 deletedAt。
@Model
final class Tombstone {
    var id: UUID          // 被删记录的 id
    var kindRaw: String
    var deletedAt: Date

    init(id: UUID, kind: TombstoneKind, deletedAt: Date) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.deletedAt = deletedAt
    }

    var kind: TombstoneKind { TombstoneKind(rawValue: kindRaw) ?? .task }
}
```

- [ ] **Step 2: 注册到 App 的 Schema**

`WorkPanel/WorkPanelApp.swift:19`,把
```swift
        let schema = Schema([TodoTask.self, BoardColumn.self, DayPlan.self])
```
改为
```swift
        let schema = Schema([TodoTask.self, BoardColumn.self, DayPlan.self, Tombstone.self])
```

- [ ] **Step 3: 构建验证**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/Models/Tombstone.swift WorkPanel/WorkPanelApp.swift
git commit -m "feat(sync): Tombstone model + register in SwiftData schema"
```

---

## Task 2: store 删除产生墓碑

**Files:**
- Modify: `WorkPanel/Store/TodoStore.swift:59-61`
- Modify: `WorkPanel/Store/BoardStore.swift:56-65`
- Test: `WorkPanelTests/TodoStoreTests.swift`、`WorkPanelTests/BoardStoreTests.swift`

- [ ] **Step 1: 写失败测试(TodoStore)**

`WorkPanelTests/TodoStoreTests.swift`:先把 `makeStore()` 的容器加上 `Tombstone.self`:
```swift
        let container = try ModelContainer(for: TodoTask.self, Tombstone.self, configurations: config)
```
再新增测试:
```swift
    @Test func deleteCreatesTaskTombstone() throws {
        let store = try makeStore()
        let task = TodoTask(title: "删我")
        store.context.insert(task)
        let id = task.id
        store.delete(task, now: Date(timeIntervalSince1970: 100))
        try store.context.save()
        #expect(try store.context.fetch(FetchDescriptor<TodoTask>()).isEmpty)
        let tombs = try store.context.fetch(FetchDescriptor<Tombstone>())
        #expect(tombs.count == 1)
        #expect(tombs.first?.id == id)
        #expect(tombs.first?.kind == .task)
        #expect(tombs.first?.deletedAt == Date(timeIntervalSince1970: 100))
    }
```

- [ ] **Step 2: 写失败测试(BoardStore)**

`WorkPanelTests/BoardStoreTests.swift`:先把 `makeStore()` 的容器加上 `Tombstone.self`:
```swift
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, Tombstone.self, configurations: config)
```
再新增两个测试:
```swift
    @Test func deleteCreatesColumnTombstone() throws {
        let store = try makeStore()
        let a = store.addColumn(name: "A")
        _ = store.addColumn(name: "B")
        try store.context.save()
        store.delete(a, now: Date(timeIntervalSince1970: 100))
        try store.context.save()
        let tombs = try store.context.fetch(FetchDescriptor<Tombstone>())
        #expect(tombs.count == 1)
        #expect(tombs.first?.id == a.id)
        #expect(tombs.first?.kind == .column)
    }

    @Test func deleteLastColumnCreatesNoTombstone() throws {
        let store = try makeStore()
        let only = store.addColumn(name: "唯一")
        try store.context.save()
        store.delete(only)
        try store.context.save()
        #expect(try store.context.fetch(FetchDescriptor<BoardColumn>()).count == 1)
        #expect(try store.context.fetch(FetchDescriptor<Tombstone>()).isEmpty)
    }
```

- [ ] **Step 3: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoStoreTests -only-testing:WorkPanelTests/BoardStoreTests`
Expected: 编译失败或断言失败(`delete` 还不接受 `now:`、未建墓碑)

- [ ] **Step 4: 实现 TodoStore.delete**

`WorkPanel/Store/TodoStore.swift`,把
```swift
    func delete(_ task: TodoTask) {
        context.delete(task)
    }
```
改为
```swift
    func delete(_ task: TodoTask, now: Date = .now) {
        let id = task.id
        context.delete(task)
        context.insert(Tombstone(id: id, kind: .task, deletedAt: now))
    }
```

- [ ] **Step 5: 实现 BoardStore.delete**

`WorkPanel/Store/BoardStore.swift`,把
```swift
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
改为
```swift
    func delete(_ column: BoardColumn, now: Date = .now) {
        let cols = columns()
        guard cols.count > 1, let target = cols.first(where: { $0.id != column.id })
        else { return }
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        for task in tasks where task.columnID == column.id {
            task.columnID = target.id
        }
        let id = column.id
        context.delete(column)
        context.insert(Tombstone(id: id, kind: .column, deletedAt: now))
    }
```

- [ ] **Step 6: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoStoreTests -only-testing:WorkPanelTests/BoardStoreTests`
Expected: 全部 PASS(含既有测试)

- [ ] **Step 7: 提交**

```bash
git add WorkPanel/Store/TodoStore.swift WorkPanel/Store/BoardStore.swift WorkPanelTests/TodoStoreTests.swift WorkPanelTests/BoardStoreTests.swift
git commit -m "feat(sync): store deletes produce tombstones"
```

---

## Task 3: 收口两处野生删除

把绕过 store 直接 `context.delete(task)` 的两处改走 `TodoStore.delete`,确保墓碑总被创建。两处都是 UI 行为路径,无单测;由构建 + Task 2 的 store 测试间接保障。

**Files:**
- Modify: `WorkPanel/UI/TaskEditorView.swift:381-387`
- Modify: `WorkPanel/UI/LensCard.swift:21-27`

- [ ] **Step 1: 改 TaskEditorView.deleteTask**

`WorkPanel/UI/TaskEditorView.swift`,把
```swift
    private func deleteTask() {
        guard case .edit(let task) = mode else { return }
        scheduler.cancel(for: task)
        context.delete(task)
        try? context.saveTracking()
        onClose()
    }
```
改为(该 view 已有 `todoStore` 计算属性):
```swift
    private func deleteTask() {
        guard case .edit(let task) = mode else { return }
        scheduler.cancel(for: task)
        todoStore.delete(task)
        try? context.saveTracking()
        onClose()
    }
```

- [ ] **Step 2: 改 LensCard 右键删除**

`WorkPanel/UI/LensCard.swift`,把 `contextMenu` 块里的
```swift
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task)
                    context.delete(task)
                    try? context.saveTracking()
                }
```
改为(该 view 已有 `todoStore` 计算属性):
```swift
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task)
                    todoStore.delete(task)
                    try? context.saveTracking()
                }
```

- [ ] **Step 3: 构建验证**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/TaskEditorView.swift WorkPanel/UI/LensCard.swift
git commit -m "refactor(sync): route UI deletes through TodoStore for tombstones"
```

---

## Task 4: 序列化(DTO + 可选字段 + 报告计数)

**Files:**
- Modify: `WorkPanel/Sync/SyncDocument.swift`
- Modify: `WorkPanel/Sync/SyncService.swift`(仅 `SyncReport`)
- Test: `WorkPanelTests/SyncDocumentTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/SyncDocumentTests.swift` 新增:
```swift
    @Test func tombstoneDTORoundTrips() throws {
        let t = Tombstone(id: UUID(), kind: .column, deletedAt: Date(timeIntervalSince1970: 123))
        let dto = SyncTombstoneDTO(t)
        let data = try SyncDocument.encoder.encode(dto)
        let back = try SyncDocument.decoder.decode(SyncTombstoneDTO.self, from: data)
        #expect(back.id == t.id)
        #expect(back.kind == "column")
        #expect(back.deletedAt == Date(timeIntervalSince1970: 123))
        #expect(back.makeModel().kind == .column)
    }

    @Test func documentMissingTombstonesDecodesAsNil() throws {
        // tombstones 为 nil → 编码省略该键(模拟旧版本文档)→ 解码回 nil
        let doc = SyncDocument(schemaVersion: 1, exportedAt: Date(timeIntervalSince1970: 0),
                               tasks: [], columns: [], dayPlans: [], settings: SyncSettingsDTO())
        let data = try SyncDocument.encoder.encode(doc)
        let back = try SyncDocument.decoder.decode(SyncDocument.self, from: data)
        #expect(back.tombstones == nil)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncDocumentTests`
Expected: 编译失败(`SyncTombstoneDTO`、`SyncDocument.tombstones` 不存在)

- [ ] **Step 3: 新增 SyncTombstoneDTO + tombstones 字段**

`WorkPanel/Sync/SyncDocument.swift`,在 `SyncDayPlanDTO` 之后、`SyncDocument` 之前插入:
```swift
struct SyncTombstoneDTO: Codable {
    var id: UUID
    var kind: String        // TombstoneKind.rawValue
    var deletedAt: Date

    init(_ t: Tombstone) { id = t.id; kind = t.kindRaw; deletedAt = t.deletedAt }

    func makeModel() -> Tombstone {
        Tombstone(id: id, kind: TombstoneKind(rawValue: kind) ?? .task, deletedAt: deletedAt)
    }
}
```
并在 `SyncDocument` 的 `settings` 字段后加(默认 `nil` 使既有构造点免传):
```swift
    var tombstones: [SyncTombstoneDTO]? = nil
```

- [ ] **Step 4: SyncReport 加删除计数**

`WorkPanel/Sync/SyncService.swift` 的 `SyncReport`,在 `settingsApplied` 字段前加:
```swift
    var tasksDeleted = 0
    var columnsDeleted = 0
```
并在 `totalUpdated` 计算属性后加:
```swift
    var totalDeleted: Int { tasksDeleted + columnsDeleted }
```

- [ ] **Step 5: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncDocumentTests`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add WorkPanel/Sync/SyncDocument.swift WorkPanel/Sync/SyncService.swift WorkPanelTests/SyncDocumentTests.swift
git commit -m "feat(sync): SyncTombstoneDTO + optional tombstones field + report counts"
```

---

## Task 5: exportData 携带墓碑

**Files:**
- Modify: `WorkPanel/Sync/SyncService.swift`(`exportData`)
- Test: `WorkPanelTests/SyncServiceExportTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/SyncServiceExportTests.swift`,在 `struct SyncServiceExportTests` 内新增(自带容器,不依赖既有 helper):
```swift
    @Test func exportIncludesTombstones() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, Tombstone.self, configurations: config)
        let ctx = ModelContext(container)
        ctx.insert(Tombstone(id: UUID(), kind: .task, deletedAt: Date(timeIntervalSince1970: 5)))
        try ctx.save()

        let data = try SyncService.exportData(context: ctx, includeSettings: false)
        let doc = try SyncService.parse(data)
        #expect(doc.tombstones?.count == 1)
        #expect(doc.tombstones?.first?.kind == "task")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceExportTests`
Expected: 断言失败(`doc.tombstones` 为 nil)

- [ ] **Step 3: 实现**

`WorkPanel/Sync/SyncService.swift` 的 `exportData`,在 `let plans = ...` 后加一行 fetch:
```swift
        let tombs   = try context.fetch(FetchDescriptor<Tombstone>())
```
并在 `SyncDocument(...)` 构造里 `settings:` 行后加:
```swift
            tombstones: tombs.map(SyncTombstoneDTO.init)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceExportTests`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Sync/SyncService.swift WorkPanelTests/SyncServiceExportTests.swift
git commit -m "feat(sync): exportData includes tombstones"
```

---

## Task 6: merge 应用墓碑(核心)

**Files:**
- Modify: `WorkPanel/Sync/SyncService.swift`(`merge`)
- Test: `WorkPanelTests/SyncServiceMergeTests.swift`

- [ ] **Step 1: 升级测试 helper**

`WorkPanelTests/SyncServiceMergeTests.swift`,把 `makeContext()` 的容器加上 `Tombstone.self`:
```swift
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, Tombstone.self, configurations: config)
```
并把 `docWith(...)` 改为接受 `tombstones`:
```swift
    private func docWith(tasks: [SyncTaskDTO] = [], columns: [SyncColumnDTO] = [],
                         dayPlans: [SyncDayPlanDTO] = [],
                         tombstones: [SyncTombstoneDTO] = [],
                         settings: SyncSettingsDTO = SyncSettingsDTO()) -> SyncDocument {
        SyncDocument(schemaVersion: 1, exportedAt: .now,
                     tasks: tasks, columns: columns, dayPlans: dayPlans,
                     settings: settings, tombstones: tombstones)
    }
```

- [ ] **Step 2: 写失败测试(6 个)**

同一文件新增:
```swift
    @Test func tombstoneDeletesLocalTask() throws {
        let ctx = try makeContext()
        let local = TodoTask(title: "删我")
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local); try ctx.save()
        let tomb = SyncTombstoneDTO(Tombstone(id: local.id, kind: .task,
                                              deletedAt: Date(timeIntervalSince1970: 20)))
        let report = try SyncService.merge(docWith(tombstones: [tomb]), into: ctx, includeSettings: false)
        #expect(try ctx.fetch(FetchDescriptor<TodoTask>()).isEmpty)
        #expect(report.tasksDeleted == 1)
        #expect(try ctx.fetch(FetchDescriptor<Tombstone>()).count == 1)   // 墓碑留存继续传播
    }

    @Test func tombstoneSuppressesReinsertFromThirdDoc() throws {
        let ctx = try makeContext()
        let id = UUID()
        let tomb = SyncTombstoneDTO(Tombstone(id: id, kind: .task,
                                              deletedAt: Date(timeIntervalSince1970: 20)))
        _ = try SyncService.merge(docWith(tombstones: [tomb]), into: ctx, includeSettings: false)
        // 第三设备仍持活任务(改动早于删除),无墓碑
        let live = TodoTask(title: "复活?")
        live.modifiedAt = Date(timeIntervalSince1970: 10)
        var dto = SyncTaskDTO(live); dto.id = id
        let report = try SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(try ctx.fetch(FetchDescriptor<TodoTask>()).isEmpty)   // 未复活
        #expect(report.tasksInserted == 0)
    }

    @Test func newerEditSupersedesTombstone() throws {
        let ctx = try makeContext()
        let id = UUID()
        let tomb = SyncTombstoneDTO(Tombstone(id: id, kind: .task,
                                              deletedAt: Date(timeIntervalSince1970: 20)))
        _ = try SyncService.merge(docWith(tombstones: [tomb]), into: ctx, includeSettings: false)
        let edited = TodoTask(title: "改后")
        edited.modifiedAt = Date(timeIntervalSince1970: 30)   // 晚于删除
        var dto = SyncTaskDTO(edited); dto.id = id
        let report = try SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        let tasks = try ctx.fetch(FetchDescriptor<TodoTask>())
        #expect(tasks.count == 1)                       // 复活
        #expect(tasks.first?.title == "改后")
        #expect(report.tasksInserted == 1)
        #expect(try ctx.fetch(FetchDescriptor<Tombstone>()).isEmpty)   // 墓碑被撤销
    }

    @Test func tombstoneTieDeletes() throws {
        let ctx = try makeContext()
        let id = UUID()
        let tomb = SyncTombstoneDTO(Tombstone(id: id, kind: .task,
                                              deletedAt: Date(timeIntervalSince1970: 20)))
        _ = try SyncService.merge(docWith(tombstones: [tomb]), into: ctx, includeSettings: false)
        let same = TodoTask(title: "同刻")
        same.modifiedAt = Date(timeIntervalSince1970: 20)   // 与删除相等
        var dto = SyncTaskDTO(same); dto.id = id
        let report = try SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(try ctx.fetch(FetchDescriptor<TodoTask>()).isEmpty)   // 删除胜
        #expect(report.tasksInserted == 0)
    }

    @Test func unknownTombstoneIsHarmless() throws {
        let ctx = try makeContext()
        let tomb = SyncTombstoneDTO(Tombstone(id: UUID(), kind: .task,
                                              deletedAt: Date(timeIntervalSince1970: 20)))
        let report = try SyncService.merge(docWith(tombstones: [tomb]), into: ctx, includeSettings: false)
        #expect(report.tasksDeleted == 0)
        #expect(try ctx.fetch(FetchDescriptor<Tombstone>()).count == 1)   // 仍留存继续传播
    }

    @Test func tombstoneDeletesLocalColumn() throws {
        let ctx = try makeContext()
        let col = BoardColumn(name: "删列", order: 0)
        col.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(col); try ctx.save()
        let tomb = SyncTombstoneDTO(Tombstone(id: col.id, kind: .column,
                                              deletedAt: Date(timeIntervalSince1970: 20)))
        let report = try SyncService.merge(docWith(tombstones: [tomb]), into: ctx, includeSettings: false)
        #expect(try ctx.fetch(FetchDescriptor<BoardColumn>()).isEmpty)
        #expect(report.columnsDeleted == 1)
    }
```

- [ ] **Step 3: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceMergeTests`
Expected: 断言失败(merge 尚未处理墓碑:记录未删、`tasksDeleted` 恒为 0)

- [ ] **Step 4: 重写 merge**

`WorkPanel/Sync/SyncService.swift`,把整个 `merge(_:into:includeSettings:calendar:)` 函数体替换为:
```swift
    /// 按 ID 合并(DayPlan 按归一化 day),最新者胜;墓碑传播删除并抑制复活。
    /// 刻意用普通 save() 以保留文件时间戳。
    @discardableResult
    static func merge(_ doc: SyncDocument, into context: ModelContext,
                      includeSettings: Bool, calendar: Calendar = .current) throws -> SyncReport {
        var report = SyncReport()

        // 本地映射(task / column / 墓碑),供墓碑阶段与抑制判断复用
        let existingTombs = try context.fetch(FetchDescriptor<Tombstone>())
        var tombByID = Dictionary(uniqueKeysWithValues: existingTombs.map { ($0.id, $0) })
        let cols = try context.fetch(FetchDescriptor<BoardColumn>())
        var colByID = Dictionary(uniqueKeysWithValues: cols.map { ($0.id, $0) })
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        var taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // 阶段一:合并传入墓碑,并按(合并后的)墓碑时间删除本地记录
        for dto in doc.tombstones ?? [] {
            if let local = tombByID[dto.id] {
                if dto.deletedAt > local.deletedAt { local.deletedAt = dto.deletedAt }
            } else {
                let t = dto.makeModel(); context.insert(t); tombByID[dto.id] = t
            }
            let at = tombByID[dto.id]!.deletedAt
            if let task = taskByID[dto.id], task.modifiedAt <= at {
                context.delete(task); taskByID[dto.id] = nil; report.tasksDeleted += 1
            }
            if let col = colByID[dto.id], col.modifiedAt <= at {
                context.delete(col); colByID[dto.id] = nil; report.columnsDeleted += 1
            }
        }

        // 列(先于任务,使 columnID 引用可解析)
        for dto in doc.columns {
            if let tomb = tombByID[dto.id], tomb.deletedAt >= dto.modifiedAt { continue }   // 删除胜
            if let local = colByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.columnsUpdated += 1 }
            } else {
                let c = dto.makeModel(); context.insert(c); colByID[dto.id] = c; report.columnsInserted += 1
            }
            if let tomb = tombByID[dto.id], dto.modifiedAt > tomb.deletedAt {
                context.delete(tomb); tombByID[dto.id] = nil   // 复活:撤销被超越的墓碑
            }
        }

        // 任务
        for dto in doc.tasks {
            if let tomb = tombByID[dto.id], tomb.deletedAt >= dto.modifiedAt { continue }   // 删除胜
            if let local = taskByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.tasksUpdated += 1 }
            } else {
                let t = dto.makeModel(); context.insert(t); taskByID[dto.id] = t; report.tasksInserted += 1
            }
            if let tomb = tombByID[dto.id], dto.modifiedAt > tomb.deletedAt {
                context.delete(tomb); tombByID[dto.id] = nil   // 复活:撤销被超越的墓碑
            }
        }

        // 日计划(按 day 匹配)
        var plans = try context.fetch(FetchDescriptor<DayPlan>())
        for dto in doc.dayPlans {
            let day = calendar.startOfDay(for: dto.day)
            if let local = plans.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                if dto.modifiedAt > local.modifiedAt {
                    dto.apply(to: local)
                    report.dayPlansUpdated += 1
                }
            } else {
                let p = dto.makeModel()
                p.day = day
                context.insert(p); plans.append(p); report.dayPlansInserted += 1
            }
        }

        if includeSettings { SyncSettings.apply(doc.settings); report.settingsApplied = true }

        try context.save()
        return report
    }
```

- [ ] **Step 5: 跑测试确认通过(含既有合并用例)**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/SyncServiceMergeTests`
Expected: 全部 PASS(6 个新用例 + 既有 task/column/dayPlan/settings 用例无回归)

- [ ] **Step 6: 提交**

```bash
git add WorkPanel/Sync/SyncService.swift WorkPanelTests/SyncServiceMergeTests.swift
git commit -m "feat(sync): merge applies tombstones (delete propagation + resurrection guard)"
```

---

## Task 7: 全量回归

- [ ] **Step 1: 逐 suite 跑全部受影响测试**

Run(分次,避免全包卡死):
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/SyncServiceMergeTests \
  -only-testing:WorkPanelTests/SyncDocumentTests \
  -only-testing:WorkPanelTests/SyncServiceExportTests \
  -only-testing:WorkPanelTests/TodoStoreTests \
  -only-testing:WorkPanelTests/BoardStoreTests
```
Expected: 全部 PASS

- [ ] **Step 2: 构建整包确认 UI 改动无编译问题**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

---

## Self-Review(已执行)

- **Spec coverage**:模型(Task 1)、删除收口(Task 2/3)、序列化+兼容(Task 4)、导出(Task 5)、merge 算法+6 场景(Task 6)、回归(Task 7)。spec 每节均有对应任务。残留墓碑属 GC 非目标,无需任务。
- **Placeholder scan**:无 TBD/TODO,每个 code step 均含完整代码。
- **Type consistency**:`Tombstone(id:kind:deletedAt:)`、`TombstoneKind.{task,column}`、`SyncTombstoneDTO(_:)`/`makeModel()`、`SyncDocument.tombstones`、`SyncReport.{tasksDeleted,columnsDeleted,totalDeleted}`、`TodoStore.delete(_:now:)`、`BoardStore.delete(_:now:)` 在各任务间命名一致。
- **兼容性**:`schemaVersion` 全程保持 1;`tombstones` 可选默认 nil,既有构造点(测试 `docWith`、`exportData`)免改即编译。
