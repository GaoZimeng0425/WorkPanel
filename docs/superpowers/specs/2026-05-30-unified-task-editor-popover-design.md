# 统一任务编辑/创建 Popover 设计

日期：2026-05-30
分支：feature/todo-app

## 背景与问题

当前点击列表 / 看板里的任务卡片没有任何反应——详情/编辑功能根本未实现。卡片（`TaskCardView`）只支持：

- 左侧圆圈按钮：标记完成
- 列表卡片右侧 `⋯` 菜单：推迟 / 删除
- 看板卡片：拖拽移动列、右键删除

任务的字段（标题、备注、截止时间、优先级、标签、重复规则、所属看板列）目前只能在创建时设定，创建后无法修改。`notes` 字段甚至从未在任何 UI 出现。

同时存在两个割裂的创建入口：

1. `CaptureView`：全局快捷键的自然语言快速录入面板（输入 `写周报 明天17:00 !高 #周报`，实时解析成 chips）。**不能选状态。**
2. 看板列底 `AddTaskField`：内联快速输入框，自动归到当前列。

## 目标

1. 点击任务卡片弹出可编辑的详情 popover。
2. 创建与编辑**共用同一个表单组件**。
3. 创建时可以选择"状态"（开发中 / 测试中 等）。

## 关键决策

### 状态 = 看板列（复用，不加数据字段）

任务的"状态"在现有数据结构里已经通过 `TodoTask.columnID: UUID?` 指向某个 `BoardColumn` 来表达。看板每一列就是一个状态，默认三列为 `计划中 / 开发中 / 测试中`，用户可自建列。

**不新增独立的 status 枚举字段**——那会和看板列形成两套并行的状态概念，需要写同步逻辑且容易打架。本设计零数据结构改动。

状态选择器列出当前所有 `BoardColumn` + 一个「无状态」项（`columnID = nil`，仅存在于 TODO 列表、不上看板）。

### CaptureView 保留

自然语言快速捕获是核心的快速录入路径，原样保留，不动。新表单是与之共存的结构化入口，不替换它。

### 看板列底 `AddTaskField` 保留

内联快速输入框保留（超快、状态隐含为本列）。结构化表单创建是另一个更完整的入口，不合并。

## 架构

### 新增组件

**`TaskEditorView`**（新文件 `WorkPanel/UI/TaskEditorView.swift`）

结构化表单，只负责表单内容，不负责自己如何被弹出。两种模式共用此视图：

| 字段 | 控件 | 写入 |
|---|---|---|
| 标题 | `TextField` | `task.title` |
| 备注 | `TextEditor`（多行） | `task.notes` |
| 截止时间 | 开关 + `DatePicker`，可清空 | `task.deadline` |
| 优先级 | 分段选择器 高/中/低 | `task.priority` |
| 标签 | chips（带 ✕ 删除）+ 小输入框追加 | `task.tags` |
| 重复 | `Menu`：无/每天/工作日/每周/每月 | `task.recurrence` |
| 状态 | `Picker`：所有看板列 + 「无状态」| `task.columnID` |

### 两种模式

`TaskEditorView` 通过一个 `Mode` 区分行为：

```swift
enum Mode {
    case edit(TodoTask)              // 绑定已存在任务
    case create(columnID: UUID?)     // 空草稿，可预选状态
}
```

**编辑模式**
- 绑定已存在的 `TodoTask`（`@Bindable`），字段改动实时写回模型并 `context.save()`。
- 改状态：更新 `columnID`，并把 `boardOrder` 设为目标列当前任务数（放到列末尾）；选「无状态」则 `columnID = nil`。
- popover 关闭时按需重排提醒：调用 `scheduler.schedule(for: task)`（其内部会先 cancel 再按当前 deadline 重新调度；deadline 为空或已过则不调度）。

**创建模式**
- 表单为一张空的本地草稿状态（`@State`，未落库）；从看板某列打开时状态预选该列。
- 底部「保存」按钮 / `⌘↩`（与 CaptureView 一致）才真正：构造 `TodoTask` → 写 `columnID` 与 `boardOrder` → `context.insert` → `context.save()` → `scheduler.schedule(for:)`。
- 未确认前不落库。标题为空（trim 后）时不保存，与现有 `CaptureView.save` / `AddTaskField` 行为一致。
- `esc` 取消，不创建。

### 呈现方式

两种模式都用 `.popover`：

- **编辑**：popover 锚在被点击的卡片上。
- **创建**：popover 锚在 `+` 按钮上。

通过一个 `ViewModifier`（持有 `@State private var showEditor`）封装"点击→弹 popover"，挂在调用方的卡片 / 按钮上，使 `TaskCardView` 保持纯展示、契约不变。

### 触发入口改动

| 位置 | 改动 |
|---|---|
| `TaskListView.row` | 卡片加点击手势 → 弹编辑 popover |
| `TaskListView` | 加一个 `+` 入口（footer 或 header）→ 弹创建 popover（`columnID = nil`）|
| `BoardView.card` | 卡片加点击手势 → 弹编辑 popover；与现有 `.draggable` / `.contextMenu` 共存 |
| `BoardView` 每列 | 列头/列内加一个 `+` 入口 → 弹创建 popover，预选该列；现有列底 `AddTaskField` **保留不变** |

## 副作用与边界

- **提醒调度**：编辑改了截止时间 / 标题 / 备注后需重排通知。统一在 popover 关闭时调用一次 `scheduler.schedule(for:)`（幂等：先 cancel 再调度），避免每次按键都重排。创建保存时同样调用一次。
- **看板排序 `boardOrder`**：编辑改状态或创建落到某列时，`boardOrder` 取该列当前活动任务数（追加到末尾），与 `BoardView.addTaskField` 现有逻辑一致。
- **点击 vs 拖拽（看板，风险项）**：看板卡片同时有 `.draggable` 和点击手势。macOS 上单击（无位移）触发点击、拖动（有位移）触发 draggable，二者通常可共存，但**必须实跑验证**，确认点击弹 popover 不会误触发拖拽、拖拽不会误弹 popover。
- **点击不误触卡片内按钮**：卡片左侧完成圆圈、右侧 `⋯` 菜单是 `Button`，会优先消费点击，不应触发编辑 popover。点击手势作用于卡片主体区域。
- **标签输入**：追加输入框按空格 / 回车分隔；去重；去掉空白项。
- **截止时间清空**：用一个开关控制 `deadline` 是否存在；关掉则 `deadline = nil`。

## 不做（YAGNI）

- 不新增 status 数据字段。
- 不替换 `CaptureView`，不替换看板列底 `AddTaskField`。
- 不做拖拽排序之外的状态管理。
- 创建模式不做实时草稿持久化。

## 验收标准

1. 点击列表 / 看板任意未完成卡片主体 → 弹出编辑 popover，显示该任务的全部字段当前值。
2. 编辑任一字段 → 关闭 popover 后再次打开，值已保留（已落库）。
3. 编辑修改截止时间 → 通知按新时间调度（旧的被取消）。
4. 编辑里改状态 → 列表/看板中任务出现在对应看板列。
5. 列表 `+` → 弹创建 popover（状态默认「无状态」）；看板列 `+` → 弹创建 popover（状态预选该列）。
6. 创建模式填标题后 `⌘↩` / 保存 → 任务出现在所选状态对应位置；`esc` → 不创建。
7. 创建模式标题为空时保存无效果。
8. 看板卡片点击弹 popover 与拖拽移动列互不干扰（实跑验证）。
9. 点击卡片完成圆圈 / `⋯` 菜单不会弹出编辑 popover。
10. `CaptureView` 与看板列底 `+ 添加任务` 行为不变。
