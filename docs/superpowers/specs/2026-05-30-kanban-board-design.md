# 看板面板(Kanban Board Panel)设计

日期:2026-05-30
状态:已确认,待实现

## 背景

WorkPanel 是一个 macOS 菜单栏 agent 应用(SwiftUI + SwiftData,Swift 6)。现有能力:

- `TodoTask` 模型:title、notes、deadline、priority、tags、isCompleted/completedAt、createdAt、snoozedUntil、recurrence。
- `TodoStore`:任务 CRUD、循环任务、snooze。
- `TaskFilter`:今天 / 即将到期 / 全部 / 归档(归档 = `isCompleted`)。
- `PanelController`:居中浮动 `NSPanel`,承载快速捕获视图;失焦自动消失。
- `HotkeyManager`:全局快捷键 ⌘⌥J 切换捕获面板。
- `TaskListView`:菜单栏 `MenuBarExtra` 里的列表(今天/即将到期/全部 + 归档)。

## 目标

新增一个**看板面板**:按快捷键从**屏幕底部向上滑出、铺满底部宽度**,把所有任务以看板列(计划中 / 开发中 / 测试中 / 归档…)的形式展示。用户可自定义列,可在列间拖拽任务。

看板是现有任务的**另一个视图**——菜单栏的今天/即将到期/全部/归档视图保持不变,共用同一批 `TodoTask` 数据。

## 数据模型

### 新增 `BoardColumn`(`Models/BoardColumn.swift`)

```swift
@Model
final class BoardColumn {
    var id: UUID
    var name: String
    var order: Int
}
```

代表用户可自定义的「活动阶段」列。

### `TodoTask` 增加字段

- `columnID: UUID?` —— 任务所在的活动列。
- `boardOrder: Int` —— 列内手动排序索引(越小越靠前)。

两者均有默认值(`columnID = nil`、`boardOrder = 0`),通过 SwiftData 轻量迁移加入,不破坏现有数据。`SharedModel` 的 `Schema` 增加 `BoardColumn.self`。

### 「归档」是内置虚拟列

- 归档**不是** `BoardColumn` 记录,而是 `isCompleted == true` 的渲染呈现。
- 已完成任务一律显示在归档列,与 `columnID` 无关。
- 完成时 `columnID` **保留不变**,以便「恢复(reopen)」时任务回到原来的活动列。

## 行为与规则

### 首次启动播种(由 `BoardStore` 负责,仅执行一次)

- 当库中没有任何 `BoardColumn` 时,插入三列:`计划中`(order 0)、`开发中`(order 1)、`测试中`(order 2)。
- 现有**未完成**任务的 `columnID` 设为第一列(计划中);其 `boardOrder` 按现有 `TaskFilter.sortRule` 的顺序赋值,保证不是随机序。
- 已完成任务无需赋列(它们显示在归档)。

### 新建任务的默认列

- 看板列底「+ 添加任务」与现有 ⌘⌥J 捕获面板新建的任务,默认 `columnID` = 第一列(order 最小的列)。

### 列内排序

活动列内为手动顺序:按 `boardOrder` 升序。拖拽调整顺序时重算受影响任务的 `boardOrder`。

归档列不使用 `boardOrder`,沿用现有 `TaskFilter.archived` 的排序(按 `completedAt` 倒序)。

### 列管理

- 列头「⋯」菜单:**改名**、**删除**。
- 列末尾「+ 添加列」:新建列,`order` 取当前最大值 +1。
- 删除某列时,列内任务的 `columnID` 改为第一列(计划中);任务不丢失。
- **约束**:至少保留 1 个活动列(不能删到 0 列)。归档列是虚拟列,不可删除、不可改名、不可手动新建。

## 组件划分

| 文件 | 职责 |
|---|---|
| `Models/BoardColumn.swift`(新增) | 列模型 |
| `Store/BoardStore.swift`(新增) | 列 CRUD(增 / 改名 / 重排 / 删→任务移到第一列)、任务移列、列内重排、首启播种 |
| `UI/BoardView.swift`(新增) | 看板 UI:横向列、卡片、拖拽、列底「+添加任务」、列头「⋯」菜单、「+添加列」 |
| `UI/BoardPanelController.swift`(新增) | 底部上滑 `NSPanel`,滑入/滑出动画,仅 Esc/快捷键收起 |
| `System/HotkeyManager.swift`(改) | 新增 `toggleBoard` 快捷键名,默认 ⌘⌥K |
| `WorkPanel/WorkPanelApp.swift`(改) | `AppDelegate` 注册看板快捷键、接线看板面板;`Schema` 增加 `BoardColumn.self` |
| `UI/SettingsView.swift`(改) | 增加看板快捷键录制器 |

## 关键交互

### 拖拽(核心)

- SwiftUI `.draggable` + `.dropDestination`,载荷为任务 `UUID`(`Transferable`)。
- 落入某活动列:设置 `columnID`,并按落点重算 `boardOrder`。
- 列内拖动:调整 `boardOrder`。
- 拖入归档列:等同标记完成(走 `TodoStore.complete`,保留循环/提醒逻辑)。
- 从归档拖出到某活动列:`TodoStore.reopen`,任务回到目标列。

### 列底新建

输入标题后复用现有 `InputParser` 解析 `#标签`、`!优先级`、截止时间等语法;新任务 `columnID` = 该列。

### 卡片操作

与现有保持一致,**不做完整编辑视图**:

- 完成勾选:走 `TodoStore.complete`(保留循环任务生成 + 取消/重排提醒调度)。
- 拖拽移动 / 重排。
- 右键(或「⋯」)菜单:删除(同时 `ReminderScheduler.cancel`)。

卡片展示:标题、优先级圆点、截止时间(过期标红)、循环标记、标签。

## 面板行为(`BoardPanelController`)

- `NSPanel`,`styleMask` 含 `.nonactivating`,`level = .floating`,`isFloatingPanel = true`。
- 铺满当前屏幕 `visibleFrame` 宽度(留左右边距),高度固定约 360pt,贴底部对齐。
- 显示:从屏幕下方(frame 起点在可见区下方)滑入到位(动画 origin 向上)。
- 收起:Esc 键或再次按快捷键 → 向下滑出后 `orderOut`。
- `hidesOnDeactivate = false`,**不**实现 `windowDidResignKey` 自动消失(区别于捕获面板,看板是「干活」面板,需要拖拽 / 输入 / 开菜单)。

## 错误与边界处理

- 删除列 → 任务移到第一列;不能删除最后一个活动列。
- 归档列不可删 / 改名 / 新建。
- 完成任务保留 `columnID`,恢复时回到原列。
- 任务 `columnID` 指向已不存在的列(理论上不应发生)→ 视为第一列渲染。

## 测试(沿用现有内存 `ModelContainer` 风格,见 `TodoStoreTests`)

`BoardStore` 单元测试:

- 增列 / 改名 / 重排列。
- 删列:列内任务 `columnID` 移到第一列;不能删到 0 列。
- 移动任务到另一列:`columnID` 更新。
- 列内重排:`boardOrder` 正确递增 / 不冲突。
- 看板内完成:任务进归档(`isCompleted`),循环任务生成下一次,`columnID` 保留。
- 恢复(reopen):任务回到原 `columnID` 列。
- 首启播种:无列时建 3 列;现有未完成任务归入第一列,`boardOrder` 按 `sortRule` 顺序。

## 非目标(本次不做)

- 卡片完整编辑视图(标题/备注/截止/优先级/标签的修改 UI)。
- 看板列的颜色 / 图标自定义。
- 多看板(多个 board)。
- 跨设备同步。
