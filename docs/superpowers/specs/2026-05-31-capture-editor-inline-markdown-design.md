# 设计：单文本域 · 行内实时渲染的捕获编辑器

日期：2026-05-31
状态：已与用户确认，待评审

## 背景

`021fd39` 重构后，创建/编辑任务统一走捕获面板（`PanelController` → `TaskEditorView`）。
当前 `TaskEditorView` 使用 `TaskFormFields` 富表单（独立标题框、备注框、截止时间、
优先级、标签、重复、所在列选择器）。

本次三项需求：

1. 看板底部的「+ 添加任务」也走捕获面板（与列头 `+` 一致）。
2. 编辑器收敛为**单个文本域**，第一行作为标题。
3. markdown 支持，且**边写边渲染**——编辑时即显示渲染后的样式，不分栏。

## 关键决策（已确认）

- **结构化字段来源**：用既有 `InputParser` 从第一行解析（截止/优先级/标签/重复），
  而非独立控件。所在列来自上下文（看板 `+` 传入的 `columnID`），不在文本中输入。
- **编辑保留语义**：「缺省即保留，不清除」——编辑既有任务时，第一行未出现某 token
  则保留原值。代价：编辑态无法通过删除 token 来清除截止/标签/重复（罕见，后续可加清除入口）。
- **渲染方式**：行内实时渲染、不分栏。采用**方案 A（标记可见的实时样式）**：
  标题/加粗/斜体/行内代码/引用/列表在编辑中即时套用样式，`#` `**` `-` 等标记仍可见。
  放弃 Typora 式隐藏标记的真 WYSIWYG（方案 B：需自定义 TextKit 布局管理器，体量大且脆弱）。
- **依赖**：**不引入 markdown 库**。MarkdownUI 等仅能展示、不可编辑，无法承载「编辑即渲染」。
  改为自写 `NSViewRepresentable` 包裹 `NSTextView`，用 TextKit 套用属性。

## 组件与改动

### 1. 看板「+ 添加任务」走捕获面板（需求 #1）

- `BoardView.swift:124` 处对 `addTaskField(column)` 的使用改为一个外观一致的按钮
  （`+ 添加任务`、plain、小字号），点击后 post `.openTaskEditor` →
  `TaskEditorView.Mode.create(columnID: column.id)`。与列头 `+`（`BoardView.swift:103`）一致。
- 由此产生的孤儿，按「清理自己造成的孤儿」原则删除：
  - `addTaskField(_:)` 方法（`BoardView.swift:135–148`，含其中的 `InputParser().parse` 内联新增逻辑）。
  - `AddTaskField` 私有视图（`BoardView.swift:235–246`）。
- `scheduler`（`ReminderScheduler`）在 BoardView 其它位置仍使用（201/228/229），保留。
- 列头 `+` 不动；列表视图的新增（`TaskListView.swift:72`）已走面板，不动。

### 2 + 3. `TaskEditorView` 收敛为单文本域 + 行内实时渲染（需求 #2/#3）

#### 新组件 `MarkdownTextEditor`（`NSViewRepresentable`）

- 包裹 `NSTextView`（置于 `NSScrollView` 内），双向绑定整段文本 `String`。
- 文本变化时由一个**样式器**扫描并套用 TextKit 属性（标记保留可见）：
  - 标题 `#`/`##`/`###` → 行字号加大、加粗。
  - 加粗 `**…**` / `__…__` → 粗体；斜体 `*…*` / `_…_` → 斜体。
  - 行内代码 `` `…` `` → 等宽 + 轻微背景。
  - 引用 `> ` → 缩进 + 次要色；无序 `- `/`* `/`+ ` 与有序 `1. ` → 列表样式/缩进。
  - **第一行**额外以「标题样式」（更大/半粗）呈现，呼应「第一行即标题」。
- 键盘（结合既有面板层处理，见 PanelController/KeyablePanel）：
  - 普通 `Return` = 换行（多行编辑）。
  - `⌘Return` = 保存：在 coordinator 中拦截转发给保存动作，避免被 NSTextView 吞掉。
  - `esc` = 取消：经 `KeyablePanel.onCancel` 关闭面板（既有机制）。

#### token 条（解析预览）

- 编辑器**上方**一行 SwiftUI 状态条（非第二栏），随输入实时显示从第一行解析出的
  截止/优先级/标签/重复 chips。空则不显示对应 chip。

#### 解析/保存逻辑（抽成纯函数，便于测试）

新增可测纯函数（如 `CaptureDraft.resolve(text:base:now:defaultPriority:)`），输入整段文本与
基准值（编辑=既有任务，创建=默认），输出 `(title, notes, deadline, priority, tags, recurrence)`：

```
firstLine = text 第一行；body = 其余行原文（markdown 原样）
parsed = InputParser().parse(firstLine, now: now, defaultPriority: base.priority)
title      = parsed.title                                  // 去空白后为空则禁用保存
notes      = body
deadline   = parsed.deadline   ?? base.deadline            // 缺省即保留
tags       = parsed.tags.isEmpty ? base.tags : parsed.tags // 缺省即保留
recurrence = parsed.recurrence ?? base.recurrence          // 缺省即保留
priority   = parsed.priority                               // parse 以 base.priority 为默认
column     = 来自上下文（create 的 columnID）/ 既有 task.columnID
```

- 创建：`base` = 空/默认（`priority = AppSettings.defaultPriority`）。
- 编辑：`base` = 既有任务。seeding——第一行=既有 `title`，其余=既有 `notes`；
  既有 截止/优先级/标签 在 token 条展示。
- 保存动作沿用现有：创建走 `TodoStore.add` + `BoardStore.setColumn`；
  编辑直接改既有对象；之后 `context.save()` 与 `ReminderScheduler.schedule`。

#### 视图布局

- 冻雾卡片，`VStack`：标题（新建/编辑任务）→ token 条 → `MarkdownTextEditor`（填充，
  可滚动，约 220 高）→ 按钮（取消 / 保存 ⌘↩）。宽度沿用 ~560（单栏，无需加宽）。

### 清理

- `TaskFormFields`（`WorkPanel/UI/TaskFormFields.swift`）仅被 `TaskEditorView` 使用，
  改造后成为孤儿，删除。

## 测试

- **纯逻辑（单测）**：对 `CaptureDraft.resolve` 覆盖——第一行解析、body 提取、
  「缺省即保留」（编辑态不丢 截止/优先级/标签/重复）、空标题禁用保存。
- `InputParserTests` 已覆盖 token 解析本身，不重复。
- **AppKit 渲染/键盘/布局**：运行 app 人工验证（`NSTextView` 样式无单测）。

## 已知取舍 / 非目标

- 不做隐藏标记的真 WYSIWYG（方案 B）。
- 编辑态无法通过删空 token 清除 截止/标签/重复（按用户确认，可接受）。
- 不引入任何第三方 markdown 依赖。
