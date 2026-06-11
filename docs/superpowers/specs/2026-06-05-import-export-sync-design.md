# 导入 / 导出(跨机器同步)设计

日期:2026-06-05

## 目标

WorkPanel 无联网能力。用户希望通过手动导出一个文件、在另一台机器导入,实现两台机器之间的数据同步。

## 同步语义

导出写出一个自包含的 JSON 文件。导入采用 **按 ID 合并 + 最新者胜(newest-wins)**:

- **任务(TodoTask)** — 按 `id` 匹配。本地不存在 → 插入;已存在 → 仅当文件中的记录 `modifiedAt` 更新时覆盖本地。
- **看板列(BoardColumn)** — 按 `id` 匹配,同样的最新者胜规则。
- **日计划(DayPlan)** — `DayPlan` 没有 `id`,按归一化后的 `day`(当天 00:00)匹配,同样的最新者胜规则。
- **设置(Settings)** — 仅当用户在导入时勾选「同时导入设置」才应用。勾选后,白名单内的所有键覆盖本地;密钥(AI API Key、MCP Token)以明文包含在文件中。
- **时间戳相等** → 跳过(保留本地),保证确定性。

### 不支持的语义(已确认接受)

**删除不传播**。在 A 机删除一个任务,只是让它从 A 的导出中消失;导入到 B 时不会重新添加它,但 B 也不会删除自己的副本。传播删除需要 tombstone(软删除 + 保留期),复杂度显著上升,本设计明确不做。删除是按机器手动操作。

## 模型变更:可靠的 `modifiedAt`

最新者胜需要每条记录上一个可信的时间戳。为三个 `@Model` 增加:

```swift
var modifiedAt: Date = .now
```

涉及 `TodoTask`、`BoardColumn`、`DayPlan`。这是 SwiftData 轻量迁移(带默认值的新存储属性):已有行在迁移时获得默认值(约等于升级时刻),首次导出时会被正常打点。各 `init` 也将 `modifiedAt` 初始化为 `.now`(或对应的 `createdAt`/`day`,以保持语义一致 —— 实现时统一用 `.now` 即可,简单且足够)。

### 打点机制:`saveTracking()` 助手(已选定)

为避免把打点逻辑散落到各处,新增:

- `Timestamped` 协议:`var modifiedAt: Date { get set }`,由三个模型 conform。
- `ModelContext.saveTracking()` 扩展方法:保存前,遍历 `insertedModelsArray + changedModelsArray`,把其中 `Timestamped` 的对象的 `modifiedAt` 置为 `.now`,然后 `try save()`。

随后把现有约 28 处 `context.save()` 调用点机械替换为 `context.saveTracking()`(`try? context.save()` → `try? context.saveTracking()`,MCP 里 `try context.save()` → `try context.saveTracking()`)。每一处改动都直接服务于「可靠 modifiedAt」这一需求。

**导入合并路径刻意使用普通 `context.save()`**(不是 `saveTracking()`),以便保留来自文件的时间戳,而不是用 `.now` 重新打点。

调用点清单(实现时核对):
`WorkPanelApp.swift`、`TaskEditorView.swift`(×2)、`TaskListView.swift`(×4)、`BoardView.swift`、`KanbanLensView.swift`(×5)、`PriorityLensView.swift`、`LensCard.swift`(×2)、`PlanningView.swift`(×3)、`TodayLensView.swift`、`MCPToolHandlers.swift`(×7)。

> 备选方案(未采用):单点的 `ModelContext.willSave` 通知观察者。优点是只改一处,缺点是 SwiftData 在 willSave 中再次置脏的行为较脆弱,且导入时需要一个抑制标志。为可测试性选择显式 `saveTracking()`。

## 文件格式

单个 JSON 文件:

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-06-05T08:00:00Z",
  "tasks": [
    {
      "id": "UUID",
      "title": "…",
      "notes": "…",
      "deadline": "ISO8601 或 null",
      "priorityRaw": 1,
      "tags": ["…"],
      "isCompleted": false,
      "completedAt": "ISO8601 或 null",
      "createdAt": "ISO8601",
      "snoozedUntil": "ISO8601 或 null",
      "recurrenceRaw": "… 或 null",
      "columnID": "UUID 或 null",
      "boardOrder": 0,
      "planOrder": 0,
      "urgencyOverride": true,
      "modifiedAt": "ISO8601"
    }
  ],
  "columns":  [ { "id": "UUID", "name": "…", "order": 0, "modifiedAt": "ISO8601" } ],
  "dayPlans": [ { "day": "ISO8601", "committedTaskIDs": ["UUID"], "modifiedAt": "ISO8601" } ],
  "settings": { "<key>": <value> }
}
```

- 全保真 DTO,放在新的 `Sync/` 模块。**不复用 MCP 的 `TaskDTO`** —— 它有损(丢弃 `createdAt`、`recurrence`、`planOrder`、`snoozedUntil`、`urgencyOverride` 等)。
- 日期统一用 ISO8601(复用 `ISO8601Date`,可处理带/不带小数秒)。
- 设置为白名单内 `AppSettings.Key` 键的字典。值类型异构(Int / Bool / String / Double),用现有 `JSONValue`(MCP 模块)或等价的 Codable 包装编码。`aiPrompts` 在 UserDefaults 中本身就是 JSON 字符串,原样作为字符串导出。
- 设置**不需要** `modifiedAt`:用户选择「导入时勾选确认」,因此设置没有最新者胜逻辑,勾选即整体覆盖。

### 设置白名单键

来自 `AppSettings.Key`:`reminderLeadMinutes`、`appearance`、`notificationSound`、`defaultPriority`、`boardViewMode`、`mcpEnabled`、`mcpPort`、`mcpToken`、`boardHeight`、`aiBaseURL`、`aiModel`、`aiAPIKey`、`aiPrompts`。
**不导出** `lastPlannedDay`(开工规划状态,属于本机当日状态,不应跨机器覆盖)。

## 新增模块

- `WorkPanel/Sync/SyncDocument.swift` — `Codable` 顶层文档 + `SyncTaskDTO` / `SyncColumnDTO` / `SyncDayPlanDTO` 及设置编码。
- `WorkPanel/Sync/SyncService.swift` — `@MainActor`:
  - `exportData(context:) throws -> Data` — 抓取三类模型 + 读取白名单设置,编码为 `SyncDocument`。
  - `parse(_ data: Data) throws -> SyncDocument` — 解码并校验 `schemaVersion`。
  - `merge(_ doc: SyncDocument, into context:, includeSettings: Bool) -> SyncReport` — 纯粹、可测的合并单元;用普通 `context.save()` 落库。
  - `SyncReport`:`{ tasksInserted, tasksUpdated, columnsInserted, columnsUpdated, dayPlansInserted, dayPlansUpdated, settingsApplied: Bool }`。
- `WorkPanel/Sync/Timestamped.swift` — `Timestamped` 协议 + `ModelContext.saveTracking()`。
- `WorkPanel/Sync/SyncSettings.swift` — 读/写白名单 `AppSettings.Key`(导出读取、导入写入)。

> 新文件位于 `WorkPanel/` 下,filesystem-synced group 自动纳入,无需改 `project.pbxproj`。

## 合并逻辑细节

```
for dto in doc.columns:
    local = fetch column by dto.id
    if local == nil: insert new BoardColumn from dto (含 modifiedAt)
    else if dto.modifiedAt > local.modifiedAt: 覆盖 name/order/modifiedAt
    else: skip

for dto in doc.tasks:
    local = fetch task by dto.id
    if local == nil: insert new TodoTask from dto(全字段, 含 modifiedAt)
    else if dto.modifiedAt > local.modifiedAt: 覆盖全部可变字段 + modifiedAt
    else: skip

for dto in doc.dayPlans:
    local = fetch DayPlan by 归一化 day
    if local == nil: insert new DayPlan from dto
    else if dto.modifiedAt > local.modifiedAt: 覆盖 committedTaskIDs + modifiedAt
    else: skip

if includeSettings:
    for key in whitelist: 写入 UserDefaults
    settingsApplied = true

context.save()   // 普通 save,保留文件时间戳
```

合并顺序:先列、后任务、再日计划(任务引用 columnID,但合并不强制外键有效性 —— 渲染层已对取不到的 ID 容错,无需级联校验)。

## UI

在现有 **通用(general)** 设置 tab 内新增一张 **「数据同步」** 卡片,沿用现有 `section`/`row` 的磨砂卡片风格(不新增 tab):

- **导出…** → `NSSavePanel`,默认文件名 `WorkPanel-备份-YYYY-MM-DD.json` → `SyncService.exportData` → 写文件 → `Notice("已导出")`。
- **导入…** → `NSOpenPanel`(限 `json`)→ `parse` → 弹确认对话:
  - 文案:`将合并 N 个任务 / M 个看板列 / K 个日计划`
  - 复选框:`同时导入设置(含 API Key 等密钥)`,默认不勾。
  - 按钮:`取消` / `导入`。
  - 确认后 → `merge(includeSettings:)` → `Notice("导入完成:新增 x,更新 y")`。
  - 若导入了设置:重新 `Appearance.apply()`,并发 `.mcpSettingsChanged` 通知以重启 MCP。

SettingsView 增加少量 `@State`:解析后的 `SyncDocument`、是否显示确认、`includeSettings` 开关。文件面板与确认弹窗用 AppKit/SwiftUI 既有方式。

## 错误处理

- JSON 损坏 / 无法解码 / 未知 `schemaVersion` → 捕获 → `Notice("导入失败:文件格式无效")`。
- 导出写文件失败 → `Notice("导出失败")`。
- 不对「不可能发生」的情况加防御代码。

## 测试

复用内存 `ModelContainer` 模式(参照 `BoardStoreTests` / `TodoStoreTests`):

- 合并:插入新增、较新者覆盖、较旧者跳过、时间戳相等跳过。
- DayPlan 按 day 匹配(同日不同时刻视为同一天)。
- 设置:勾选则应用、不勾选则不动本地设置。
- 导出 → 导入到空 context 的往返一致(全字段保真)。
- `saveTracking()` 对 inserted/changed 的 `Timestamped` 对象打点 `modifiedAt`;普通 `save()` 不打点。
- DTO 编解码往返(含可选字段为 nil 的情形)。

## 范围之外(YAGNI)

- tombstone / 删除传播。
- 自动同步、文件监视、网络。
- 设置的细粒度最新者胜(已选「导入时确认」整体覆盖)。
- 加密导出文件(密钥明文,已确认)。
