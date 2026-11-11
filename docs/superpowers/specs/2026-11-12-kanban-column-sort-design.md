# 看板列排序 — 设计

日期:2026-11-12
状态:待确认

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
