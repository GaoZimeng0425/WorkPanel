# 同步删除传播(墓碑机制)设计

**日期**:2026-06-07
**状态**:待实现
**关联**:[2026-06-05-import-export-sync](./2026-06-05-import-export-sync-design.md)、[2026-06-06-lan-auto-sync](./2026-06-06-lan-auto-sync-design.md)

## 问题

`SyncService.merge()` 只遍历传入文档的 `tasks` / `columns`,无法获知「某记录曾存在但已被删除」。后果:在设备 A 删除一条任务后,任一仍持有该记录的对端会在下一轮同步时把它**重新插入**,任务/列「复活」。LAN 自动同步每 30s 拉取一次,使复活几乎必然发生。

DayPlan 从不被删除(只 `ensurePlan` 创建,无删除路径),自动排除。

## 目标

- 删除一条 `TodoTask` 或 `BoardColumn` 后,删除能跨设备传播,且不被对端复活。
- 改动锁在「删除路径 + 序列化 + merge」三处;`@Query`、UI、各 lens 视图、`exportData` 调用方均不改动逻辑。
- 与现有「整记录 LWW(最新者胜)」语义一致。

## 非目标(YAGNI)

- 墓碑裁剪 / GC —— 永久保留,每条仅一个 UUID + 时间,个人量级可忽略。
- DayPlan 墓碑 —— 从不删除。
- 字段级冲突解决 —— 维持现有整记录 LWW。

## 方案:独立墓碑模型

删除时硬删原记录并插入一条墓碑;同步文档携带墓碑数组;merge 时墓碑既删除本地记录,又抑制来自第三方文档的重新插入。

选此方案而非「软删除标志位」:软删需在每一处 `@Query` / `FetchDescriptor` / `exportData` / MCP `list_tasks` 加 `deletedAt == nil` 过滤,漏一处即出现幽灵行,爆炸半径大;墓碑模型让记录真删,查询与 UI 完全不碰。

## 设计细节

### 1. 新增模型 `Tombstone`

```swift
// WorkPanel/Models/Tombstone.swift
@Model final class Tombstone {
    var id: UUID          // 被删记录的 id
    var kindRaw: String   // TombstoneKind.rawValue
    var deletedAt: Date

    init(id: UUID, kind: TombstoneKind, deletedAt: Date) {
        self.id = id; self.kindRaw = kind.rawValue; self.deletedAt = deletedAt
    }
    var kind: TombstoneKind { TombstoneKind(rawValue: kindRaw) ?? .task }
}

enum TombstoneKind: String, Codable { case task, column }
```

- 加入 `SharedModel.container` 的 schema:`Schema([TodoTask.self, BoardColumn.self, DayPlan.self, Tombstone.self])`。**纯增量**变更(新表),SwiftData 轻量迁移自动处理,无需迁移计划。
- `Tombstone` **不**实现 `Timestamped`:它从不被编辑;merge 走普通 `save()` 不会重新打点 `deletedAt`。

### 2. 删除路径收口

所有删除统一经 store,store 负责「硬删 + 建墓碑」。`deletedAt` 默认 `.now`,可注入以便测试。

- `TodoStore.delete(_ task: TodoTask, now: Date = .now)`:
  `context.delete(task)` + `context.insert(Tombstone(id: task.id, kind: .task, deletedAt: now))`
- `BoardStore.delete(_ column: BoardColumn, now: Date = .now)`:
  保留现有逻辑(库中 >1 列时,列内任务移到首列)+ `context.delete(column)` + 插入 `.column` 墓碑。
  注意:只在真正删除发生时建墓碑(只剩一列时现有逻辑直接 `return`,不删也不建墓碑)。

收口两处当前绕过 store 的野生删除:

- `WorkPanel/UI/TaskEditorView.swift:384` `context.delete(task)` → `todoStore.delete(task)`(该 view 已有 `todoStore` 计算属性)。
- `WorkPanel/UI/LensCard.swift:24` `context.delete(task)` → `TodoStore(context: context).delete(task)`。

MCP `delete_task`(`MCPToolHandlers.swift:168` 的 `todo.delete(task)`)与 `TaskListView.swift:143` 的 `store.delete(task)` 已走 `TodoStore.delete`,自动获得墓碑,无需改动。

### 3. 序列化

```swift
// SyncDocument.swift
struct SyncTombstoneDTO: Codable {
    var id: UUID
    var kind: String       // TombstoneKind.rawValue
    var deletedAt: Date
    init(_ t: Tombstone) { id = t.id; kind = t.kindRaw; deletedAt = t.deletedAt }
    func makeModel() -> Tombstone {
        Tombstone(id: id, kind: TombstoneKind(rawValue: kind) ?? .task, deletedAt: deletedAt)
    }
}

struct SyncDocument: Codable {
    static let currentSchemaVersion = 1          // 保持 1
    var schemaVersion: Int
    var exportedAt: Date
    var tasks: [SyncTaskDTO]
    var columns: [SyncColumnDTO]
    var dayPlans: [SyncDayPlanDTO]
    var settings: SyncSettingsDTO
    var tombstones: [SyncTombstoneDTO]?          // 新增,可选以向后兼容
    // ... encoder / decoder 不变
}
```

**兼容性**:`schemaVersion` 保持 **1**;`tombstones` 设为可选。

- 旧文档(无 `tombstones` 字段)解码 → `nil`,merge 时按空数组处理。
- 旧版 App 收到带 `tombstones` 的 v1 文档:JSONDecoder 默认忽略未知键,任务/列照常同步,仅不处理删除。升级后自愈。
- 不 bump 到 2 是为避免混合版本期间因「严格版本相等」校验导致设备间**完全停止同步**。

`exportData` 增加:
```swift
let tombs = try context.fetch(FetchDescriptor<Tombstone>())
// doc 构造中: tombstones: tombs.map(SyncTombstoneDTO.init)
```
`SyncPeerServer` 经 `SyncService.exportData(context:includeSettings:false)` 导出,自动携带墓碑。

### 4. merge 算法

在现有 columns / tasks / dayPlans 合并**之前**先处理墓碑;task / column 合并时查墓碑以抑制复活。

```
incoming = doc.tombstones ?? []
建本地墓碑表 localTomb: [UUID: Tombstone](fetch Tombstone,task + column 两类同表按 id)

# 阶段一:合并传入墓碑
for dto in incoming:
    if let local = localTomb[dto.id]:
        if dto.deletedAt > local.deletedAt { local.deletedAt = dto.deletedAt }   # 保留较晚者
    else:
        let t = dto.makeModel(); context.insert(t); localTomb[dto.id] = t
    # 用(合并后的)墓碑时间删除本地记录
    let at = localTomb[dto.id]!.deletedAt
    若存在 id==dto.id 的本地 TodoTask/BoardColumn 且 record.modifiedAt <= at:
        context.delete(record); 计入 report

# 阶段二:合并 tasks(columns 同理,顺序仍是 columns 先于 tasks)
for dto in doc.tasks:
    if let tomb = localTomb[dto.id], tomb.deletedAt >= dto.modifiedAt:
        continue                          # 删除胜:不插不更
    # 否则正常 LWW insert/update(现有逻辑)
    ... 现有 insert/update ...
    if let tomb = localTomb[dto.id], dto.modifiedAt > tomb.deletedAt:
        context.delete(tomb); localTomb[dto.id] = nil   # 复活:撤销被超越的墓碑
```

语义与不变量:

- **平局**(`deletedAt == modifiedAt`):删除胜(用 `>=`),确定性。
- **删除 vs 并发编辑**:晚者胜。删除晚 → 保持删除;对端编辑更晚 → 记录带新内容复活,并撤销本地墓碑。
- **3 设备收敛**:A 删任务产生墓碑;C 仍持活任务。合并 A 文档:删本地副本 + 留墓碑。之后合并 C 文档(有活任务、无墓碑):阶段二查到墓碑且 `deletedAt >= 任务 modifiedAt` → 抑制重新插入。不复活。✅
- merge 仍以普通 `context.save()` 结束(保留文件时间戳,不重新打点)。
- **残留墓碑(可接受)**:若某设备的本地编辑(未经 merge)晚于一条传入墓碑,该设备保留活记录、墓碑滞留其本地库。此墓碑被更新的活记录全程压制,无害;其它设备经阶段二会撤销该墓碑;唯一保留它的是「本地编辑取胜」那台设备。属 GC 范畴(非目标),不额外处理。
- 列墓碑删除本地列后,该列下的本地任务 `columnID` 成为悬空引用 —— 与现有「按 ID 取任务取不到即跳过 / 卡片仍显示但归属未知」行为一致,本设计不额外处理(非删除传播范畴)。

`SyncReport` 增加删除计数(用于状态文案),例如:
```swift
var tasksDeleted = 0
var columnsDeleted = 0
// totalDeleted 计算属性
```
`SyncCoordinator.syncAll` 的状态文案可顺带展示「删除 N」,非必须。

## 测试

此库测试密集,新增覆盖:

**`SyncServiceMergeTests`**
- 传入墓碑删除本地已存在的 task / column。
- 墓碑抑制第三方文档对同一 id 的重新插入(3 设备场景)。
- 传入 task 的 `modifiedAt` 晚于本地墓碑 `deletedAt` → 记录复活且本地墓碑被撤销。
- 平局(`deletedAt == modifiedAt`)→ 删除胜。
- 未知 id 的墓碑无害(无本地记录时不报错、不产生副作用)。
- column 墓碑路径与 task 对称。

**`TodoStoreTests` / `BoardStoreTests`**
- `delete` 后产生对应 `kind` 的墓碑且原记录已删。
- `BoardStore.delete` 在只剩一列时不删除、不建墓碑。

**`SyncDocumentTests`**
- 含 `tombstones` 的 `SyncDocument` 编解码往返一致。
- 缺 `tombstones` 字段的旧文档解码 → `tombstones == nil`,merge 按空处理(向后兼容)。

## 验收标准

1. 设备 A 删除任务/列后,设备 B 在下一轮同步移除对应记录,且后续轮次不复活。
2. 旧版本文档(无 tombstones)仍能被新版 merge 正常处理。
3. 所有新增与既有同步测试通过;`@Query` / UI / `exportData` 调用方无行为回归。
