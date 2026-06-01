# 捕获面板显式控件 — 设计

> 给捕获/编辑面板（`TaskEditorView`）加三个显式控件：重要程度、状态（看板列）、标签多选；
> 让控件成为 priority/tags/columnID 的唯一来源，文本域只保留标题、截止/重复/紧急 token 与备注。

日期：2026-05-31 · 分支：`feature/todo-app`

## 背景

今天 `TaskEditorView` 是单个 markdown 文本域：第一行用自然语言 token
（`明天 18:00 !高 #工作 每周一 !紧急`）解析出 deadline / priority / tags / recurrence / urgencyOverride，
其余行作备注。解析在 `InputParser.parse` 完成，`CaptureDraft.resolve` 负责"缺省即保留"合并，
`TokenStrip` 实时回显解析结果。

`priority` 与 `tags` 只能靠记 token 语法输入，缺少直观控件；`columnID`（看板列，
默认列为 `计划中 / 开发中 / 测试中`）目前只能在看板里拖拽设置，捕获时无法选。

## 目标

在捕获面板内直接：
1. **重要程度** — 选 `Priority`（低/中/高）。
2. **状态** — 选任务所属看板列（`BoardColumn`），含「无」。
3. **标签** — 多选已有标签并可新建。

## 决策（已与用户确认）

- **控件为 priority / tags 的唯一来源**：不再从第一行解析 `!高` / `#标签`。
  `deadline` / `recurrence` / `urgencyOverride` 仍走第一行 token。
- **`InputParser` 不改动**（通用解析器，有测试覆盖）。priority/tags 的覆盖只发生在
  `TaskEditorView` 保存路径上。
- **状态**用 `Menu`，选项与看板共用同一份 `BoardColumn` 数据（天然同步）。
- **标签**用 **popover 多选**（GitHub Labels / Notion 多选属性 风格）：
  收起态显示摘要，点开后顶部输入框同时负责筛选与新建。
- **重要程度**用现有 `NoirSegmented` 三段。

## 数据流改动

保存时字段来源拆分如下：

| 字段 | 来源 |
|---|---|
| `title` | `text` 第一行（经 `InputParser` 去除 token 后的标题词） |
| `notes` | `text` 其余行 |
| `deadline` | 第一行 token（不变） |
| `recurrence` | 第一行 token（不变） |
| `urgencyOverride` | 第一行 token（不变） |
| **`priority`** | **重要程度控件 `@State`** |
| **`tags`** | **标签控件 `@State`** |
| **`columnID`** | **状态控件 `@State`** |

实现方式：`TaskEditorView.save()` 仍调用 `CaptureDraft.resolve` 拿 title/notes/deadline/recurrence/urgency，
然后用控件状态**覆盖** `fields.priority` 与 `fields.tags`；`columnID` 经 `boardStore.setColumn` 写入。
解析器解析出的 priority/tags 被丢弃（不入库）。

### `@State` 与初始化

`TaskEditorView` 新增三个 `@State`，在 `init` 中从 `base` / `mode` 播种：

- `@State private var priority: Priority` ← create：`AppSettings.defaultPriority`；edit：`task.priority`
- `@State private var selectedTags: [String]` ← create：`[]`；edit：`task.tags`
- `@State private var columnID: UUID?` ← create：`mode` 传入的 columnID（捕获热键为 `nil`）；edit：`task.columnID`
  （现有的 `let columnID` 改为 `@State`。）

读取已有标签全集供 popover 选择：`@Query private var allTasks: [TodoTask]`，
`Array(Set(allTasks.flatMap(\.tags))).sorted()`。看板列：`@Query`（按 `order` 排序）或
`boardStore.columns()`，二者皆可，优先 `@Query` 保持响应式。

## UI 组件

### 布局

在编辑器文本域**下方**、footer（取消/保存）**上方**插入一个控件区，三行纵向排列：

```
重要程度   [低｜中｜高]              ← NoirSegmented
状态       [计划中 ▾]               ← Menu
标签       [工作 等4个标签 ▾]        ← Popover trigger（pill）
```

每行用一个轻量 label + 控件的 `HStack`，沿用 Theme 字号/颜色。

### 1. 重要程度 — `NoirSegmented<Priority>`

复用现有 `NoirSegmented`，三段 `低 / 中 / 高`，`selection` 绑定 `$priority`。
段标签用 `Theme.priorityLabel`。

### 2. 状态 — `Menu`

- trigger：pill（`NoirPillButtonStyle` 外观或等价），显示当前列名；`columnID == nil` 显示「无」。
- 菜单项：遍历看板列，点选设 `columnID = col.id`；末尾一项「无」设 `columnID = nil`。
- 选中项加 `checkmark`。

### 3. 标签 — Popover 多选

- **收起态 trigger**（pill）摘要规则：
  - 0 个：占位「标签」（textTertiary）
  - 1–3 个：空格连接全名，如 `工作 学习`
  - \>3 个：`<首个标签> 等<总数>个标签`，如 `工作 等4个标签`
- **popover 内容**（竖直、不换行）：
  - 顶部 `TextField`：输入实时过滤下方已有标签列表。
  - 列表：已有标签（与过滤词匹配的）逐行，行内勾选切换是否在 `selectedTags` 中（`checkmark`）。
  - **新建**：当输入词非空且与任何已有标签都不精确相等时，列表顶部出现一行
    「新建『<输入词>』」；点选或回车即把该词加入 `selectedTags`（并随任务保存自然进入标签全集），
    清空输入框。
  - 已选标签用 `Theme.tag` 绿色风格呈现（与卡片 `noirBadge(Theme.tag)` 一致）。

popover 用 SwiftUI `.popover`；其中 `TextField` 可正常输入（这正是不用原生 `Menu` 的原因）。

### TokenStrip 收窄

`TokenStrip` 去掉 priority 与 tag chip，仅保留 token 派生项：截止 / 重复 / 紧急。
底部提示文案从「可在第一行用如『明天 !高 #工作』补充」改为
「可在第一行用如『明天 18:00 每周一』补充」。

## 不做（YAGNI）

- 不把 `urgencyOverride` 改成控件（用户未要求，保留 `!紧急` token）。
- 不改 `InputParser` / `CaptureDraft` 的解析逻辑或其测试。
- 不做标签重命名/删除管理（只在此面板多选与新建）。
- 不抽象通用「popover 多选」组件（当前单处使用，遵循项目"≥2 次才抽取"约定）。

## 测试

- **保留通过**：`InputParserTests`、`CaptureDraftTests`（解析器与 resolve 未改）。
- **新增（编辑器保存逻辑层）**：验证控件为准——
  - 重要程度设「高」、文本第一行写 `!低` → 入库 `priority == .high`（token 被忽略）。
  - 标签控件选 `["工作"]`、文本写 `#别的` → 入库 `tags == ["工作"]`。
  - 状态选某列 → `task.columnID` 等于该列 id；选「无」→ `nil`。
  - 截止/重复/紧急仍来自 token（回归不丢）。
  - 由于这些断言依赖 `save()` 的字段组装，若 `save()` 难以脱离 SwiftData/视图单测，
    则把"控件覆盖解析结果"的纯逻辑抽成一个可测的小函数（输入：resolved fields + 控件值，
    输出：最终 fields）并对其断言。
- **UI**：仅冒烟。SwiftUI 自定义控件交互（popover/Menu）不依赖 XCUITest 驱动
  （见记忆 `xcuitest-cannot-drive-swiftui-draggable` 的同类约束），逻辑覆盖走单元层。

## 验收

- 捕获面板能不靠记 token 语法，直接选重要程度、状态、标签（含新建）。
- 保存后任务的 priority/tags/columnID 与控件一致；deadline/recurrence/紧急仍可由第一行 token 设置。
- 编辑已有任务时三个控件正确回显当前值。
- 既有解析器测试全绿。
