# 看板多透镜视图设计(看板 / 四象限 / 今日 / 优先级)

日期:2026-05-31
状态:已批准,待实现

## 背景与目标

WorkPanel 是一个工作记录应用。当前看板(`BoardView`)用自定义列(`BoardColumn`)横向排列活动任务,外加一个虚拟「归档」列,支持列间拖拽。

本次在看板标题栏增加 **tab 切换器**,把同一批活动任务用多种工作法「透镜」重新组织。v1 落地 4 个透镜:

1. **看板** — 现有列布局,不变。
2. **象限** — 艾森豪威尔矩阵:重要×紧急 的 2×2。
3. **今日** — 今日到期 + 逾期 的聚焦列表。
4. **优先级** — 按 高/中/低 分组。

核心原则:**透镜是同一批任务的不同分组视角**,任务始终保留它的看板列;切 tab 不改变任务归属,只改变展示与可拖拽编辑的维度。

## 数据模型

### 维度来源(已定)

- **重要(important)** 复用现有 `priority`:`高/中 → 重要`,`低 → 不重要`。不新增字段。
- **紧急(urgent)** 默认从 `deadline` 推导,允许手动覆盖。新增**一个**可选布尔字段。

### `TodoTask` 变更

新增一个存储字段:

```swift
var urgencyOverride: Bool?   // nil = 自动(看 deadline), true = 强制紧急, false = 强制不紧急
```

新增两个非持久化计算访问器:

```swift
static let urgentWindow: TimeInterval = 48 * 3600   // 默认 48 小时(含逾期);常量,可改

var isImportant: Bool { priority != .low }          // 高/中 = 重要

func isUrgent(asOf now: Date = .now) -> Bool {
    if let o = urgencyOverride { return o }
    guard let d = deadline else { return false }
    return d <= now.addingTimeInterval(Self.urgentWindow)
}
```

`isUrgent(asOf:)` 取 `now` 参数以便测试;视图内调用默认参数。

### 迁移

新增可选属性属于 **SwiftData 轻量自动迁移**,无需迁移计划。已有任务的 `urgencyOverride` 为 `nil`,即「自动」模式,行为与今天一致(仅由 deadline 决定是否紧急)。

## 视图架构

把现在单体的 `BoardView` 拆成 **外壳 + 4 个透镜视图**,避免单文件承担过多职责:

| 单元 | 职责 | 依赖 |
|---|---|---|
| `BoardView`(外壳) | 标题栏 + tab 切换器;持有 `@AppStorage("boardViewMode")`;按模式切换 body;保留 esc/onClose、设置按钮 | 各透镜视图 |
| `BoardViewMode`(新枚举) | `{ kanban, matrix, today, priority }`,带中文 label 与 SF Symbol | — |
| `KanbanLensView`(由现有 body 迁出) | 现有列布局:列、归档列、新建/重命名/删除列、列间拖拽 | `BoardStore`、`LensCard` |
| `MatrixLensView`(新) | 2×2 象限网格 | `BoardStore`、`LensCard` |
| `TodayLensView`(新) | 今日到期 + 逾期 单列表 | `LensCard` |
| `PriorityLensView`(新) | 高/中/低 三列 | `BoardStore`、`LensCard` |
| `LensCard`(新,共享) | 包装现有 `TaskCardView`:点按编辑 + 完成 + 删除 contextMenu + `draggable` | `TaskCardView` |

`KanbanLensView` 由当前 `BoardView` body 原样迁出,行为不变(包括重命名/新建列的 alert)。

tab 切换器:标题栏内的分段控件(segmented control),位于「看板」标题与 ⚙️ 之间,风格与应用一致(磨砂卡片风)。

## 各透镜行为与拖拽语义

| 透镜 | 布局 | 拖拽落入时设置 |
|---|---|---|
| 看板 | 不变 | 列 + 顺序(不变) |
| 象限 | 2×2:重要紧急 / 重要不紧急 / 不重要紧急 / 不重要不紧急 | 重要度:低⇄中;紧急度:`urgencyOverride = true/false` |
| 今日 | 单列表:逾期 + 今日到期(按 `deadline`) | 无拖拽;仅点按编辑 + 完成 |
| 优先级 | 三列 高/中/低 | `priority` |

### 已定的判断点

- **象限的重要度拖拽是有损的(设计如此)**:把一个 `高` 任务拖入「不重要」象限会被设为 `低`(高/中 粒度坍缩为布尔)。在「重要」侧的两个象限之间拖拽不改变 priority 级别。
- **紧急度覆盖仅通过两处设置**:象限拖拽,以及卡片 contextMenu 的「强制紧急 / 取消强制」开关。v1 **不**改动 markdown token 编辑器/解析器(保持改动最小)。
- **今日仅按 `deadline` 计算 —— 不新增「手动聚焦」字段**(YAGNI)。

各透镜需有友好的空状态文案。

## Store

扩展 `BoardStore`:

```swift
func setQuadrant(_ task: TodoTask, important: Bool, urgent: Bool)
func setPriority(_ task: TodoTask, to priority: Priority)
```

`setQuadrant` 的映射:

- `important == true`:若当前 `priority == .low` 则设为 `.medium`;否则保留(`高` 不被降级为 `中`)。
- `important == false`:设为 `.low`。
- `urgent`:写 `urgencyOverride = urgent`(始终显式 true/false)。

其余分组均为透镜视图内的读侧过滤(与现有看板一致),不进 store。

## 持久化

选中的 tab 通过 `@AppStorage("boardViewMode")` 持久化:

- 在 `AppSettings.Key` 增加常量 `boardViewMode`。
- 在 `AppSettings.registerDefaults()` 注册默认值 `.kanban`。
- 与现有 `appearance` 的写法保持一致。

## 测试

- `TodoTaskTests`:
  - `isImportant` 对每种 priority 的取值。
  - `isUrgent(asOf:)`:`urgencyOverride == nil` 且无 deadline、逾期、窗口内、窗口外;`override == true`;`override == false`。
- `BoardStoreTests`:
  - `setQuadrant` 对 4 个角落的映射正确(重要/紧急 的布尔 → priority 与 urgencyOverride)。
  - `setPriority`。
- 透镜分组是纯过滤,由上述模型测试覆盖。

## v1 范围之外(仅记录)

- ⌘1–4 键盘切 tab(需按 `panel-key-handling` 笔记在 KeyablePanel 层路由按键)。
- 「手动聚焦」字段。
