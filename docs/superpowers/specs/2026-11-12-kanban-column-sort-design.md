# 看板列排序 — 设计

日期:2026-11-12
状态:v1 已实现(401fe83..7ca8c26);同日二轮修订如下,状态待确认→已确认(用户拍板橘色 chip)

## 意图

看板(计划中/开发中/…等用户自定义列)目前列内只按手动拖拽顺序(`boardOrder`)排列。
用户要求每一列可以选择自己的排序方式,作为列的持久属性。

## 决策(已与用户确认)

- 形式:**每列固定排序方式**(持久设置),不是一次性重排动作。
- 排序依据:手动(默认)/ 优先级 / 截止日期 / 创建时间 / 标题。

## 方案

### 模型

- 新枚举 `ColumnSortOption: String`:`manual` / `priority` / `deadline` / `createdAt` / `title`。
- `BoardColumn` 增加 `var sortRaw: String?`;nil 及未知值一律回退 `manual`。
  (Optional 保证旧库行与旧同步文档解码安全。)

### 排序规则(KanbanLensView 列内未完成任务)

| 选项 | 规则 | 平局 |
|------|------|------|
| 手动 | `boardOrder` 升序(现状) | — |
| 优先级 | priorityRaw 降序 | boardOrder |
| 截止日期 | 有截止在前、早的在前,无截止殿后 | boardOrder |
| 创建时间 | 新的在前 | boardOrder |
| 标题 | `localizedStandard` A→Z | boardOrder |

用稳定排序,平局自动保持手动顺序——列内拖拽在排序列里变成「调平局次序」,无需禁用;
跨列拖入拖出照常。

### UI

列「⋯」菜单(ellipsis popover)加「排序」小节:5 行,当前项打勾(checkmark),
点击即改 `sortRaw` 并 `saveTracking()`(自动打 modifiedAt,随最新者胜同步)。
归档列不参与(仍按完成时间排)。

### 同步

`SyncColumnDTO` 增加 `var sortRaw: String?`,`init(_:)` / `apply(to:)` / `makeModel()` 带上。
旧文档缺该键解码为 nil = manual,向后兼容,`schemaVersion` 不动。

## 非目标

- 不改 Matrix / Priority / Gantt 等其他透镜(它们按各自语义排)。
- 不加排序方向(升/降)切换;方向按上表钉死。
- MCP `list_tasks` 顺序不变(仍 boardOrder)。

## 验证

- 单元测试:`ColumnSortOption` 各规则的排序正确性(含平局、无截止、未知 raw 回退);
  `SyncColumnDTO` 带 sortRaw 的编解码及旧文档缺键回退 manual。
- 看板 UI 手动确认(用户)。

---

## 二轮修订(2026-11-12,方向 + 列头 chip)

用户在 v1 上验证后提出:没有升降序、列头无排序标识。参照 shadcn DataTable 列头排序交互,
经 HTML 原型(`docs/prototypes/2026-11-12-column-sort-filter.html` v1.3,视觉与交互权威)三轮收敛:

### 定案

- **每列排序状态 = 依据 + 方向**(手动 = 无排序)。
- **方向**:升/降。各依据「常用方向」:优先级=降、截止日期=升、创建时间=降、标题=升
  (= v1 现行为)。菜单选依据即开排序并套常用方向。
- **升降语义**:升序 = 自然序(优先级低→高、截止近→远、创建旧→新、标题 A→Z);降序翻转主键,
  **无截止任务两个方向都殿后**;平局 boardOrder 决胜不变。
- **列头 chip(排序生效时常驻)**:「依据 ↑/↓」,橘色(accentText 前景 + accentSoft 底,悬浮提亮,
  细节以原型为准);点本体翻转方向;点 × 清除回手动。手动态列头无任何排序控件(与 v1 之前一致)。
- **「⋯」菜单**:排序依据 4 选(手动不再是菜单项)、当前项打勾;「方向」小节升序/降序,
  手动时置灰。
- **清除排序唯一入口 = chip 上的 ×**(菜单和其余交互都不回手动)。

### 模型与同步(增量)

- `BoardColumn.sortDescending: Bool = false`(sortRaw 为 nil=手动时无意义,置 false)。
- `ColumnSortOption`:`sorted(_:descending:)`(sorted(_:) 保留 = 常用方向,兼容既有测试与调用)、
  `preferredDescending`。
- `BoardStore`:setSort 换依据时同步写常用方向;新增 toggleSortDirection、clearSort。
- `SyncColumnDTO.sortDescending: Bool?`(旧文档缺键 → nil → apply 落 false,向后兼容)。

### 非目标(更新)

- MCP、其他透镜仍不动;不做每列自定义「常用方向」配置。
