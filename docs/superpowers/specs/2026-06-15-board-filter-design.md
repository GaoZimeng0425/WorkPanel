# 看板过滤设计

日期:2026-06-15
状态:已确认,待实现

## 目标

在看板(Board)上增加一个横向过滤栏,可按**标签、优先级、紧急度、关键字**筛选任务。过滤作用于**除 Review 外的所有透镜**(看板/矩阵/今日/优先级/甘特),在透镜间共享同一组条件。条件**不持久化**——关闭面板随 View 重建即清空。

看板列本身是「状态」维度的分组,过滤是叠加在列之上的横向筛选。

## 架构

### `BoardFilter`(新增,`Store/BoardFilter.swift`)

`@Observable` class,作为共享过滤状态:

```swift
@Observable
final class BoardFilter {
    var searchText: String = ""
    var tags: Set<String> = []
    var priorities: Set<Priority> = []
    var urgentOnly: Bool = false

    var isActive: Bool { /* 任一条件生效 */ }

    func apply(_ tasks: [TodoTask], asOf now: Date = .now) -> [TodoTask]
    func clear()
}
```

`apply` 语义(各条件之间是 AND;同一维度内是 OR):

- `searchText` 非空 → `title` 或 `notes` 包含该串(不区分大小写,trim 后判空)。
- `tags` 非空 → 任务 `tags` 与所选集合有交集(命中任一)。
- `priorities` 非空 → 任务 `priority` 在集合内。
- `urgentOnly` → `task.isUrgent(asOf: now)` 为真。

`apply` 只做过滤,不改排序/不剔除 completed——是否排除已完成由各透镜自己决定(沿用现状)。

### `BoardView` 改动

- 持 `@State private var filter = BoardFilter()`,通过 `.environment(filter)` 下发。
- header 右侧、齿轮按钮左边加漏斗按钮 `line.3.horizontal.decrease.circle`,切换过滤栏显隐(`@State private var showFilter`)。
- `filter.isActive` 时漏斗按钮以 accent 色高亮。
- **Review 透镜下隐藏漏斗按钮并自动收起过滤栏**(过滤对 Review 无效)。filter 对象不清空,切回其他透镜条件仍在。
- 过滤栏(`BoardFilterBar`)插在 header 与分隔线之间,仅 `showFilter && mode != .review` 时出现。

### `BoardFilterBar`(新增子视图)

从左到右:

- **搜索框** — 紧凑 TextField,绑定 `filter.searchText`,实时过滤。
- **优先级** — 三个可多选小药丸(高/中/低),沿用 `Theme.priority(_)` 配色;选中填充、未选描边;绑定 `filter.priorities`。
- **紧急** — 单个可切换药丸(⚡),绑定 `filter.urgentOnly`。
- **标签 ▾** — popover 列出 `Tag` 注册表(`@Query(sort: \Tag.order)`)全部标签做多选,沿用现有标签 chip 样式;按钮显示已选数量;绑定 `filter.tags`。
- **清除** — 仅 `filter.isActive` 时出现,调用 `filter.clear()`。

### 各透镜改动(看板/矩阵/今日/优先级/甘特,各 1–2 行)

加 `@Environment(BoardFilter.self) private var filter`,把 `@Query` 来的 `tasks` 在使用前过 `filter.apply(tasks)`:

- `KanbanLensView`:`activeTasks(in:)` 与 `archivedTasks` 的数据源先经 `filter.apply`。归档列是否也过滤——**过滤**(保持一致,关键字/标签同样适用于已完成卡)。
- `MatrixLensView`:`active` 计算属性基于 `filter.apply(tasks)`。
- `TodayLensView`:今日候选过滤源先经 `filter.apply`。
- `PriorityLensView`:每个优先级分组的数据源先经 `filter.apply`(注:已选优先级过滤与该透镜的优先级分组叠加,行为自洽——未选中的优先级列自然空)。
- `GanttLensView`:`rows` 源先经 `filter.apply`。

`ReviewLensView` **不改**,不接环境对象。

## 数据流

```
BoardView (@State filter)
  └─ .environment(filter)
       ├─ BoardFilterBar  ──写──▶ filter (search/tags/priorities/urgentOnly)
       └─ 各透镜  ──读──▶ filter.apply(@Query tasks) ──▶ 渲染
```

filter 是引用类型且 `@Observable`,写入即触发各透镜重渲染。

## 边界与错误处理

- **空结果**:过滤后为空时沿用各透镜现有空态文案,不额外加「无匹配结果」提示(保持简单)。
- **标签集合变化**:`Tag` 注册表删除某标签后,`filter.tags` 里可能残留已删名字——`apply` 用集合交集判断,残留名字只是匹配不到,无害;不主动清理。
- **紧急度时点**:`apply` 接受 `asOf` 参数,默认 `.now`;调用方传默认即可。
- 无需处理并发——全部 MainActor。

## 测试

`BoardFilter.apply` 是纯逻辑,单元测试覆盖:

1. 空过滤器 → 原样返回(`isActive == false`)。
2. 仅 searchText → 命中 title、命中 notes、大小写无关、trim 后空串不过滤。
3. 仅 tags → 交集命中;多标签 OR;空集合不过滤。
4. 仅 priorities → 集合内通过;空集合不过滤。
5. `urgentOnly` → 仅保留 `isUrgent(asOf:)` 为真者(传固定 `now`)。
6. 多维组合 → AND 叠加(标签+优先级同时满足才通过)。
7. `clear()` 后 `isActive == false`。

UI 不写 XCUITest(沿用项目惯例:拖拽/SwiftUI 交互靠单元测试覆盖逻辑,UI 测试仅冒烟)。

## 不做(YAGNI)

- 不持久化过滤条件。
- 不加保存的过滤预设/快捷筛选。
- 不加截止日期范围过滤(本版只做紧急度布尔)。
- 不加「无匹配结果」专门空态。
- Review 透镜不参与过滤。
