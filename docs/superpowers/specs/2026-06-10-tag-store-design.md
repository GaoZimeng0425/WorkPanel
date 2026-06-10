# 标签统一 Store(Tag registry)设计

日期:2026-06-10
分支:feature/time-range-gantt(或新开 feature 分支)

## 背景与动机

当前标签不是实体,只是每个 `TodoTask` 上的 `tags: [String]`。候选列表由视图实时从所有任务派生:

```swift
Array(Set(allTasks.flatMap(\.tags))).sorted()
```

后果:**标签一旦没有任务引用就消失**,无法保留未使用标签,也没有稳定的顺序/元数据可挂。用户需求:

1. 标签持久化,**未使用也不自动删除**。
2. 后期要加**排序**(以及可能的重命名等管理功能)。

## 方案:标签注册表(Option A)

新增 `Tag` 实体作为"标签全集 + 顺序"的权威来源。**任务仍存 `tags: [String]`(标签名)不变** —— 不触碰 TodoTask 模型、NL 解析、MCP、任务同步。Tag 表与任务通过**标签名**关联。

明确**不做**关系型(Tag↔Task 多对多):那会重写 TodoTask/NL/MCP/同步,爆炸半径过大;而重命名在本方案里也只是一次 O(N) 扫任务,不值得为自动传播重写整条管线。

### 同步范围(v1)

标签表**不进入**跨设备同步(导出/导入、LAN sync)。任务(含其 `tags` 字符串)照旧同步。merge 完成后用本地任务的标签名 **reconcile** 补齐本地 Tag 表,避免"任务上有、store 里没有"的漂移。代价:未使用标签与顺序不跨设备传播 —— 可接受,后续再加。

## 组件设计

### ① 数据模型 —— `WorkPanel/Models/Tag.swift`(新建)

```swift
@Model
final class Tag {
    @Attribute(.unique) var name: String   // 标签名,唯一;任务 tags:[String] 的引用键
    var order: Int                          // 排序地基(排序 UI 后续做)
    var modifiedAt: Date = Date()
    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }
}
extension Tag: @preconcurrency Timestamped {}
```

- **身份用 `name`(唯一)而非 UUID**:任务按名字引用;两设备各自建同名标签应天然合并,UUID 会产生重复。
- 注册进 `WorkPanelApp.swift` 的 `Schema([TodoTask, BoardColumn, DayPlan, Tombstone, Tag])`。
- `order`:先放字段,UI 不做;新建标签 `order = (现有 max order) + 1`。
- 不加 `color` 等未要求字段(YAGNI)。

### ② Store 层 —— `WorkPanel/Store/TagStore.swift`(新建,对标 BoardStore)

```swift
@MainActor
final class TagStore {
    let context: ModelContext
    init(context: ModelContext)

    func all() -> [Tag]                         // 按 order 排序
    @discardableResult func register(_ name: String) -> Tag?   // 去空白;已存在返回现有,不存在则插入(order 追加末尾)
    func register(names: [String])              // 批量,漏斗用
    func delete(_ name: String)                 // 删 Tag 行 + 扫所有任务移除该名字 + saveTracking
    func seedFromTasksIfNeeded()                // 库里无 Tag 时,从现有任务标签去重生成
    func reconcileFromTasks()                   // 确保每个任务标签名都在 store(merge 后调用)
}
```

- `delete` 把现有 `TaskEditorView.deleteTagGlobally` 的"扫任务移除名字"逻辑搬进来,并额外删除 Tag 行。
- `register` 统一 trim 空白、忽略空串、按名查重。

### ③ 注册漏斗(防漂移)

新标签的产生点都接 `register`,保证 Tag 表是任务标签名的超集:

- **picker 新建**:`onCreate` → `register`(见 ④),立即持久化。
- **NL `#标签`**:任务保存路径(`TaskEditorView` 保存、`TodoStore.add`)落库后 `register(names: task.tags)`。
- **MCP create_task / update_task**:`MCPToolHandlers` 设置 `task.tags` 后 `register(names:)`。

> 具体在哪几个 save 点插入,实现时按实际调用点收敛到最少的位置(优先任务落库的统一出口)。

### ④ TagPickerField 改造 —— `WorkPanel/UI/DesignSystem/TagPickerField.swift`

当前签名:`selected`、`existing`、`onDelete`(删除按钮已实现)。改为:

- `existing: [String]` 来源改为 `TagStore.all().map(\.name)`(按 order,不再字母序派生)。
- 新增 `onCreate: (String) -> Void`:点"新建『xxx』" → 调用方 `register` 进 store 并持久化(即使任务未保存,标签也保留)。
- `onDelete` 复用 ②的 `TagStore.delete`(全局移除、无二次确认 —— 维持已确认的删除语义)。

`create()` 内部除了把名字加入 `selected`,还要触发 `onCreate`。

### ⑤ TaskEditorView 改造 —— `WorkPanel/UI/Tasks/TaskEditorView.swift`

- `allTags` 计算属性改为读 store:`@Query private var tagEntities: [Tag]`(按 order),`existing = tagEntities.map(\.name)`。
- 删除现有 `deleteTagGlobally`,改为调用 `TagStore(context:).delete(name)`。
- TagPickerField 接上 `onCreate { TagStore(context:).register($0) }` 与 `onDelete { TagStore(context:).delete($0) }`。
- 保存任务后调用 `register(names: selectedTags)`(漏斗③)。

### ⑥ 迁移 / 首次播种

`seedFromTasksIfNeeded()` 在现有播种列的同一时机调用(`BoardStore.seedDefaultColumnsIfNeeded` 的相邻处),把已有任务标签迁入 Tag 表。

### ⑦ merge 后 reconcile

`SyncService.merge` 末尾(最终 `save()` 前)调用 `TagStore(context:).reconcileFromTasks()`,把导入任务带来的新标签名补进本地 Tag 表。Tag 行用普通 insert + 同一次 save。

## 受影响文件

| 文件 | 改动 |
|---|---|
| `Models/Tag.swift` | 新建 |
| `Store/TagStore.swift` | 新建 |
| `WorkPanelApp.swift` | Schema 加 `Tag.self`;播种处调 `seedFromTasksIfNeeded()` |
| `UI/DesignSystem/TagPickerField.swift` | 加 `onCreate`;`create()` 触发它 |
| `UI/Tasks/TaskEditorView.swift` | `allTags` 改读 store;`deleteTagGlobally` 移入 TagStore;接 onCreate/onDelete;保存后 register |
| `MCP/MCPToolHandlers.swift` | create/update 设置 tags 后 register |
| `Sync/SyncService.swift` | merge 末尾 reconcileFromTasks |

**不改**:TodoTask 模型、InputParser、SyncTaskDTO/SyncDocument、LAN 同步协议、所有读 `task.tags` 的展示视图。

## 测试

- `TagStoreTests`(单元,对标 `BoardStoreTests`):
  - `register` 去重、trim、空串忽略;`order` 递增。
  - `delete` 同时删 Tag 行并从多个任务移除名字;不影响其他标签。
  - `seedFromTasksIfNeeded` 从任务标签去重生成,库非空时不重复播种。
  - `reconcileFromTasks` 补齐缺失名字,不动已有顺序。
- 既有 `BoardStoreTests` / sync 测试保持通过。
- UI 仅冒烟(picker 交互按既有约定不做合成测试)。

## 验收标准

1. 新建标签后,**不被任何任务引用也持续存在于 picker 列表**。
2. 删除某标签 → 从所有任务移除且 Tag 行消失,无二次确认。
3. 现有任务的标签首次启动后全部出现在 Tag 表(迁移正确)。
4. NL `#标签` / MCP 建的新标签也出现在 picker 列表(漏斗生效)。
5. 导入他设备数据后,导入任务携带的新标签出现在本地 picker(reconcile 生效)。
6. `Tag.order` 字段就绪(排序 UI 本期不做)。
7. 全部既有测试 + 新增 TagStore 测试通过,`xcodebuild build` 成功。

## 明确不做(本期)

- 关系型 Tag↔Task。
- 标签跨设备同步、顺序同步。
- 排序 UI、重命名 UI、颜色。
