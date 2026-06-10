# 工作 item 时间范围 + 甘特图 tab — 设计文档

日期:2026-06-10
状态:已确认方向,待写实现计划

## 目标

1. 每个工作 item(`TodoTask`)增加"开始时间",与现有 `deadline`(截止/结束)共同构成时间范围。
2. 看板新增一个"甘特"tab,把任务按时间范围画成横条。

## 范围决策(已确认)

- **时间范围语义**:新增 `startDate`,现有 `deadline` 作为结束时间(不新增独立 endDate)。
- **粒度**:`startDate` 与 `deadline` 一致,精确到分钟,复用 `NoirDatePicker`。
- **甘特图行组织**:不分组,按 `startDate` 升序;条颜色按看板列区分。
- **时间轴**:按天;默认两周宽,横向可滑动(连续滚动,非翻页)。
- **条交互**:可拖动整条(平移)+ 可拉伸两端点(改时长)。用 `DragGesture`,**不用**看板的 `.draggable`/`.dropDestination`(后者在 macOS 上不可靠,且无法被 XCUITest 驱动)。
- **缺时间处理**:只有 `deadline`、无 `startDate` → deadline 当天单格短条;两者皆无 → 列入底部"未排期"区,不画条。

## 特性 1:item 加开始时间

### 模型
- `WorkPanel/Models/TodoTask.swift`:新增 `var startDate: Date? = nil`(带默认值 → SwiftData 轻量迁移,老数据为 nil);加进 `init`。
- `deadline` 含义不变,继续作为结束时间;提醒、紧急判定等现有逻辑不变。

### 同步
- `WorkPanel/Sync/SyncDocument.swift` 的 `SyncTaskDTO`:新增 `var startDate: Date?`,在 `init(_:)` 与 `apply(to:)` 中搬运。
- Optional + iso8601 编码 → 老 peer 发来的文档缺该键也能解码;新字段被老 peer 忽略。**纯加法,`currentSchemaVersion` 保持 1。**

### 编辑器
- `WorkPanel/UI/Tasks/TaskEditorView.swift`:在现有"时间"(deadline)行上方新增"开始"行,复用 `NoirDatePicker`,可空(不设即 nil)。沿用现有 `controlRow` 布局与样式。

### MCP
- `WorkPanel/MCP/TaskDTO.swift` 的 `TaskDTO`:输出新增 `startDate: String?`(ISO8601)。
- `WorkPanel/MCP/MCPToolHandlers.swift`:`createTask` / `updateTask` 接受 `startDate` 参数(ISO8601 字符串,可显式置 null),与现有 `deadline` 处理方式镜像。

### 校验
- 编辑器不强制 `startDate <= deadline`。
- 甘特图渲染防御性处理:若 `start > end`,按 start 当天的单格条显示。

### 明确不做
- 自然语言 `InputParser` 不解析开始时间(保持现有 deadline 解析行为)。

## 特性 2:甘特图 tab

### 渲染方案:自绘网格 + 冻结行列(方案 A)
左侧任务名列固定、顶部日期头固定,中间为可横/纵滚动的条形网格;任务条是按日期算出坐标的矩形;横向滚动靠共享水平偏移使日期头与条网格同步。

否决的备选:
- Swift Charts `RectangleMark`:坐标轴开箱即用,但"拖动整条 + 拉伸端点"在 Charts 上很别扭,而这正是核心交互。
- 固定两周按钮翻页:与"可滑动"要求冲突。

### tab 接入
- `WorkPanel/Models/BoardViewMode.swift`:末尾新增 `case gantt`,`label` = "甘特"。
- `WorkPanel/UI/Board/BoardView.swift` 的 `icon(for:)`:为 `.gantt` 加图标 `chart.bar.xaxis`。
- tab 置于末尾,不打乱现有顺序。

### 新文件
- `WorkPanel/UI/Board/GanttLensView.swift`:甘特 lens 视图。

### 行为规格
- **显示范围**:只显示未完成任务(与顶栏"X 项"口径一致);已完成任务不进甘特图。
- **行排序**:不分组。先按 `startDate` 升序;无 `startDate` 的任务按 `deadline` 排;`startDate` 与 `deadline` 皆无的进底部"未排期"区。
- **条颜色**:按看板列着色 —— 列按 `order` 索引到一组固定调色板;列数超过调色板长度时取模循环。
- **时间轴**:按天刻度;日期头固定在顶部;`dayWidth = 时间轴视口宽 / 14`(两周正好填满可视区);横向滚动查看更早/更晚日期。
- **条几何**:
  - `startDate` + `deadline` 都有 → 从 start 到 end 的横条。
  - 只有 `deadline` → deadline 当天的单格短条(start 视为当天)。
  - 只有 `startDate` → start 当天的单格短条。
  - 防御:`start > end` → start 当天单格条。
- **未排期区**:底部一个"未排期"区,列出两者皆无的任务名,不画条。**v1 交互**:点击直接打开 `TaskEditorView` 设时间。"从未排期区拖上时间轴"为后续增强,v1 不做。
- **条交互(`DragGesture`)**:
  - 拖条身 = 平移:`startDate` 与 `deadline` 同时按整天位移,保持时长。
  - 拖左端点手柄 = 改 `startDate`;拖右端点手柄 = 改 `deadline`;最小时长 1 天。
  - 落点按整天吸附。
  - 提交时:写回任务 → `context.saveTracking()`;若 `deadline` 变化则 `scheduler.cancel(for:)` + `schedule(for:)` 重排提醒;按现有编辑路径的方式更新 `modifiedAt`。

## 测试策略

- 纯逻辑抽进 `nonisolated` 几何 helper(独立 struct 或自由函数),**单测覆盖**:
  - 日期 ↔ x 坐标 换算;
  - 拖拽位移 → 新 `startDate`/`deadline`(含整天吸附、最小 1 天、平移保持时长);
  - 行排序与"未排期"分区。
- 同步往返:`SyncTaskDTO` 编解码保留 `startDate`,并兼容缺该键的老文档(扩充现有 `SyncServiceMergeTests` 或就近加测)。
- MCP:`TaskDTO` 含 `startDate`、create/update 读写 `startDate`(就近加进 `MCPToolHandlersTests`)。
- 拖拽 UI 不可被 XCUITest 驱动(项目已知约束),UI 测试仅冒烟:甘特 tab 能切换、行能渲染。

## 主要风险

- 冻结行列 + 横纵滚动同步是甘特图实现的主要风险点;几何数学已隔离为可单测 helper 以降低风险。
