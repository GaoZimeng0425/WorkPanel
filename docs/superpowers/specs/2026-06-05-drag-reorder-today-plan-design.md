# 今日规划 拖动排序 — 设计

日期:2026-06-05
分支:develop

## 目标

让「今日规划」支持拖动排序,覆盖两个界面:

1. **今日承诺 (TodayLensView)** — 显示今天已承诺任务的列表。
2. **开工规划 (PlanningView)** — 每日开工时挑选承诺任务的候选列表。

两者的拖动顺序都要**持久化**。PlanningView 的手动顺序**只作用于规划页**,不影响其他列表的排序。

## 现状

- `DayPlan.committedTaskIDs: [UUID]` 是有序数组,`PlanStore.committedTasks(on:)` 按它取任务 → TodayLensView 的顺序天然存在且可持久。
- `PlanningView.candidates` 是计算属性,按规则排序:顺延(carried)→ 建议(suggested,今天到期/逾期)→ 优先级。无持久手动顺序。
- 项目已有成熟拖拽模式(看板 / 优先级透镜):
  - `LensCard(draggable: true)` 发出 `task.id.uuidString` 作为载荷。
  - `.deferredDrop { payload in ... }`(`WorkPanel/UI/DeferredDrop.swift`)是统一落点,把数据改动推迟 ~0.35s 以盖过 macOS 拖拽影像残留。
  - 插入语义:落在某卡片上 = 插到该卡片**之前**;落在容器上 = 追加到末尾。见 `KanbanLensView.columnView`。
- `BoardStore.move` 已实现「insert-before + 同列向下移动时目标索引前移一位 + clamp」的数组重排逻辑(有 `BoardStoreTests` 覆盖)。

## 设计

### 共享纯函数

新增一个 nonisolated 纯函数(供两处复用,满足项目「重复 ≥2 次才抽象」的门槛):

```swift
nonisolated func reorderInsertingBefore(_ ids: [UUID], move id: UUID, before targetIndex: Int) -> [UUID]
```

语义与 `BoardStore.move` 的数组部分一致:
- 若 `id` 不在 `ids` 中,原样返回(no-op)。
- 移除 `id`;若其原索引 `< targetIndex`,目标索引 `-1`(向下移动补偿)。
- 目标索引 clamp 到 `[0, count-after-removal]`。
- 在目标位置插回 `id`。

容器追加场景:`targetIndex == ids.count` → 经上述逻辑落到末尾。

放在 `WorkPanel/Store/Reorder.swift`。**不重构 `BoardStore.move`**(它能工作且有测试,改动非必要)。

### TodayLensView(持久)

顺序源 = `DayPlan.committedTaskIDs`。

- 新增 `PlanStore.reorder(_ id: UUID, to index: Int, on day: Date)`:
  ```swift
  func reorder(_ id: UUID, to index: Int, on day: Date) {
      let p = ensurePlan(on: day)
      p.committedTaskIDs = reorderInsertingBefore(p.committedTaskIDs, move: id, before: index)
  }
  ```
- View:`ForEach(Array(committed.enumerated()), id: \.element.id)` → `LensCard(task:, draggable: true).deferredDrop { reorder($0, at: index) }`;外层容器 `.deferredDrop { reorder($0, at: committed.count) }`。
- 落点回调解析 payload 为 UUID → `store.reorder(id, to: index, on: now)` → `context.save()`。
- 只渲染已承诺卡片,故 payload 必然 ∈ committedTaskIDs;非法 id 经纯函数 no-op。

### PlanningView(持久,仅作用于规划页)

新增字段:`TodoTask.planOrder: Int = 0`(声明处带默认值 → SwiftData 轻量迁移自动处理,旧数据为 0)。

候选排序键改为 `(planOrder 升序, 再用现有 顺延→建议→优先级 规则做 tiebreaker)`:

```swift
.sorted { lhs, rhs in
    if lhs.planOrder != rhs.planOrder { return lhs.planOrder < rhs.planOrder }
    // 现有规则作为同序号 tiebreaker
    let lc = carriedIDs.contains(lhs.id), rc = carriedIDs.contains(rhs.id)
    if lc != rc { return lc }
    let ls = suggested(lhs, cal: cal), rs = suggested(rhs, cal: cal)
    if ls != rs { return ls }
    return lhs.priority.rawValue > rhs.priority.rawValue
}
```

- **首次拖动前**:所有任务 `planOrder == 0` → 完全由 tiebreaker 决定 → 与现有行为逐字一致,零行为变化。
- **拖动时**:把当前候选列表按新视觉顺序整体重排号 `0,1,2,…`(镜像 `BoardStore.reorder`),写回并 save。此后 `planOrder` 严格决定顺序;顺延/建议徽章仍显示,但不再影响位置。
  - 实现:用 `reorderInsertingBefore` 算出候选 id 的新顺序,再 `for (i, id) in newOrder.enumerated() { task(id).planOrder = i }`。
- 候选行加 `.draggable(task.id.uuidString)`(行本身是带勾选 toggle 的 Button,点击与拖拽共存,与 LensCard 同理)+ 每行/容器 `.deferredDrop`。

**已知取舍(文档化):** 新建或刚从 snooze 唤醒的任务 `planOrder == 0`,会出现在规划列表靠前位置。对于「每日一次」的规划界面可接受。

## 测试

(遵循约束:XCUITest 无法驱动 SwiftUI `.draggable`/`.dropDestination`;测排序逻辑而非手势。)

- `reorderInsertingBefore` 纯函数:向前移、向后移、追加到末尾、未知 id no-op、单元素/空数组边界。
- `PlanStore.reorder`:重排 committedTaskIDs 后顺序正确、save 生效。
- PlanningView planOrder 重排路径:重排号后 planOrder 连续且顺序匹配。

## 不做(YAGNI)

- 不重构 `BoardStore.move`。
- 不引入全局手动排序(planOrder 只在 PlanningView 候选排序中消费,不动 `TaskFilter.sortRule` 及其他透镜)。
- 不为「新任务落到末尾」加 max+1 计算(改动 `TodoStore.add` / MCP createTask,非必要)。
