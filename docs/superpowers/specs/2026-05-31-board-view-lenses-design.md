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

## 交互总原则:点击编辑 vs 拖拽

- 所有透镜里的卡片都**点击 → 打开编辑器**修改;在编辑器里改 `priority` / `deadline` / 紧急 token 后,任务在各透镜中自动重新归位。
- **可拖拽的透镜**仅限:
  - **看板** — 列间拖拽(改列 + 顺序),现有行为不变(列没有别的输入方式)。
  - **优先级** — 拖到 高/中/低 某列即设 `priority`(该维度无损,拖拽安全)。
- **只读展示(不可拖拽)的透镜**:象限、今日。象限不允许拖拽,正是为了避开「把高任务拖入不重要象限被降级」这类有损映射 —— 改象限归属一律走编辑器。

## 数据模型

### 维度来源(已定)

- **重要(important)** 复用现有 `priority`:`高/中 → 重要`,`低 → 不重要`。不新增字段。
- **紧急(urgent)** 默认从 `deadline` 推导,允许通过编辑器 token 手动覆盖。

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

## 编辑器 / 解析器:紧急 token

紧急度的手动覆盖通过编辑器第一行的 token 设置,与现有 `!高/!中/!低` 一致。

- `ParsedInput` 新增 `var urgencyOverride: Bool? = nil`。
- `InputParser` 新增 token 映射:
  - `!紧急` / `!urgent` → `true`
  - `!不紧急` / `!非紧急` → `false`
- `CaptureDraft.resolve` 按「缺省即保留」合并:
  `fields.urgencyOverride = parsed.urgencyOverride ?? base.urgencyOverride`。
- `TaskEditorView`:`edit` 模式把 `task.urgencyOverride` 灌入 `base`;`save` 时写回(create 经 `TodoStore.add`,edit 直接赋值)。
- `TodoStore.add` 与 `TodoTask.init` 增加 `urgencyOverride` 参数(默认 `nil`)。
- `TokenStrip` 在 `urgencyOverride == true` 时显示「紧急」chip,`== false` 时显示「不紧急」chip。

三态可达性:不输入 token = 保持现值(新任务为 `nil` 自动);`!紧急` = `true`;`!不紧急` = `false`。受现有「缺省即保留」语义限制,编辑态无法用 token 把已设的值清回 `nil`(与其它字段一致,v1 接受)。

## 视图架构

把现在单体的 `BoardView` 拆成 **外壳 + 4 个透镜视图**,避免单文件承担过多职责:

| 单元 | 职责 | 依赖 |
|---|---|---|
| `BoardView`(外壳) | 标题栏 + tab 切换器;持有 `@AppStorage("boardViewMode")`;按模式切换 body;保留 esc/onClose、设置按钮 | 各透镜视图 |
| `BoardViewMode`(新枚举) | `{ kanban, matrix, today, priority }`,带中文 label 与 SF Symbol | — |
| `KanbanLensView`(由现有 body 迁出) | 现有列布局:列、归档列、新建/重命名/删除列、列间拖拽 | `BoardStore`、`LensCard` |
| `MatrixLensView`(新) | 2×2 象限网格,只读展示 | `LensCard` |
| `TodayLensView`(新) | 今日到期 + 逾期 单列表,只读展示 | `LensCard` |
| `PriorityLensView`(新) | 高/中/低 三列,可拖拽改 priority | `BoardStore`、`LensCard` |
| `LensCard`(新,共享) | 包装现有 `TaskCardView`:点按编辑 + 完成 + 删除 contextMenu;`draggable` 为可选开关 | `TaskCardView` |

`KanbanLensView` 由当前 `BoardView` body 原样迁出,行为不变(包括重命名/新建列的 alert)。

`LensCard` 默认只读(点按编辑 + 完成 + 删除菜单);看板与优先级透镜传入 `draggable: true` 启用拖拽。

tab 切换器:标题栏内的分段控件(segmented control),位于「看板」标题与 ⚙️ 之间,风格与应用一致(磨砂卡片风)。

## 各透镜行为与拖拽语义

| 透镜 | 布局 | 拖拽 | 落入时设置 |
|---|---|---|---|
| 看板 | 不变 | ✅ 列间 | 列 + 顺序(不变) |
| 象限 | 2×2:重要紧急 / 重要不紧急 / 不重要紧急 / 不重要不紧急 | ❌ 只读 | —(改象限走编辑器:priority + 紧急 token) |
| 今日 | 单列表:逾期 + 今日到期(按 `deadline`) | ❌ 只读 | —(点按编辑 + 完成) |
| 优先级 | 三列 高/中/低 | ✅ 列间 | `priority` |

各透镜需有友好的空状态文案。

### 象限样式(`MatrixLensView`)

- **布局**:SwiftUI `Grid` 做 2×2 等分,填满内容区。四周加轴标签(顶部「紧急 / 不紧急」,左侧「重要 / 不重要」),用 `.secondary` 小字。
- **每个象限**:磨砂面板 `RoundedRectangle(cornerRadius: 10)` + `Color.primary.opacity(0.05)` 底(与现有看板列一致)。
  - header:该象限语义色的小圆点 + 同色象限名 + 计数 + 一句行动短语(马上做 / 计划做 / 尽快处理(委托) / 有空再说),短语用 `.secondary`。
  - header 下一条同色细分隔线(约 1pt,该色 ~40% 透明)。
  - 主体中性磨砂底不铺色;内部 `ScrollView` 装只读 `LensCard`。
- **语义色**:在 `Theme` 加 `nonisolated static func quadrant(important:urgent:) -> Color`:
  - 重要紧急 → `priority(.high)`(红);重要不紧急 → `deadline`(蓝);
  - 不重要紧急 → `priority(.medium)`(橙);不重要不紧急 → `priority(.low)`(灰)。

## Store

扩展 `BoardStore`:

```swift
func setPriority(_ task: TodoTask, to priority: Priority)   // 优先级透镜拖拽落入时调用
```

象限不再需要 `setQuadrant`(无拖拽)。其余分组均为透镜视图内的读侧过滤(与现有看板一致),不进 store。优先级透镜的拖拽只设 `priority`,组内顺序沿用既有排序规则,不维护 per-组的 `boardOrder`。

## 持久化

选中的 tab 通过 `@AppStorage("boardViewMode")` 持久化:

- 在 `AppSettings.Key` 增加常量 `boardViewMode`。
- 在 `AppSettings.registerDefaults()` 注册默认值 `.kanban`。
- 与现有 `appearance` 的写法保持一致。

## 测试

- `TodoTaskTests`:
  - `isImportant` 对每种 priority 的取值。
  - `isUrgent(asOf:)`:`urgencyOverride == nil` 且无 deadline、逾期、窗口内、窗口外;`override == true`;`override == false`。
- `InputParserTests`:`!紧急`/`!urgent` → `true`;`!不紧急`/`!非紧急` → `false`;无 token → `nil`。
- `CaptureDraftTests`:紧急 token 缺省即保留(`nil` 时沿用 base)。
- `BoardStoreTests`:`setPriority` 正确改 priority。
- 透镜分组是纯过滤,由上述模型测试覆盖。

## v1 范围之外(仅记录)

- ⌘1–4 键盘切 tab(需按 `panel-key-handling` 笔记在 KeyablePanel 层路由按键)。
- 「手动聚焦」字段(今日透镜仅按 `deadline` 计算)。
- 用 token 把已设的 `urgencyOverride` 清回 `nil`(受「缺省即保留」语义限制)。
