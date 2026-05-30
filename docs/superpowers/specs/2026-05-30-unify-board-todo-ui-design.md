# 统一看板与 TODO 弹窗的 UI/UX — 设计文档

日期:2026-05-30
分支:feature/todo-app

## 目标

让「看板」(`BoardView`)与「TODO 弹窗」(`TaskListView`)的视觉语言与交互体验保持一致。当前三处面板(含 `CaptureView`)各自重复实现颜色/标签逻辑,卡片布局也各画各的,导致字号、圆点尺寸、标签颜色、窗口质感都不统一。

根因是**重复**:`priorityColor` / `recurrenceLabel` 在三个文件里复制粘贴,任务单元在每个视图里独立重建。本设计通过**抽取共享层**来根除不一致,而非逐处微调。

## 范围

仅触及 UI 层。**不改动**数据模型、Store、提醒调度、拖拽逻辑。

涉及文件:
- 新增 `WorkPanel/UI/Theme.swift`
- 新增 `WorkPanel/UI/TaskCardView.swift`
- 修改 `WorkPanel/UI/TaskListView.swift`
- 修改 `WorkPanel/UI/BoardView.swift`
- 修改 `WorkPanel/UI/CaptureView.swift`
- 修改 `WorkPanel/UI/PanelController.swift`

## 三处面板的真实承载方式(重要)

- **TODO 弹窗** = `TaskListView`,经 `MenuBarExtra(...).menuBarExtraStyle(.window)` 呈现,是**系统菜单栏弹窗**。没有 `NSPanel`、没有标题栏可去,窗口由系统绘制(系统已自带毛玻璃 vibrancy + 圆角),无法把 styleMask 改成无边框。
- **Capture** = `CaptureView`,经 `PanelController`(titled、居中、560×260)呈现。
- **看板** = `BoardView`,经 `BoardPanelController`(真·无边框 + `.ultraThinMaterial`)呈现。

## 已确认的设计决策

1. **任务单元统一为「卡片」** —— TODO 列表的扁平 List row 改为与看板一致的圆角背景卡片。
2. **毛玻璃质感统一**:
   - TODO 弹窗(MenuBarExtra):**不改窗口**,用 `.scrollContentBackground(.hidden)` 让系统毛玻璃透出 List,卡片直接坐在系统材质上。
   - Capture(PanelController):外壳改为无边框 + `.ultraThinMaterial` + 14pt 圆角,与看板同款。
   - 看板:窗口外观维持现状。
3. **标签颜色统一为绿色** —— 列表/卡片原为蓝色,Capture 原为绿色;统一为绿色,使「标签(绿)」与「截止时间(蓝)」语义区分清晰。

## Part 1 — 共享样式层 `Theme.swift`(新增)

集中所有语义颜色与标签文案,作为唯一来源:

```swift
enum Theme {
    // 语义色
    static func priority(_ p: Priority) -> Color   // high .red / medium .orange / low .gray
    static let tag: Color = .green
    static let deadline: Color = .blue
    static let recurrence: Color = .purple

    // 文案
    static func priorityLabel(_ p: Priority) -> String   // 高/中/低
    static func recurrenceLabel(_ r: RecurrenceRule) -> String   // 每天/工作日/每周/每月

    // 尺寸 token
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 14
    static let titleFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let priorityDotSize: CGFloat = 7
}
```

`TaskListView`、`BoardView`、`CaptureView` 删除各自私有的 `priorityColor` / `recurrenceLabel` / `priorityLabel`,全部改调用 `Theme.*`。Capture 的标签 chip 保持绿色(已与统一决策一致),列表/卡片标签由蓝改绿。

## Part 2 — 共享组件 `TaskCardView.swift`(新增)

看板与 TODO 列表共用的唯一卡片视图,只负责**外观**;**行为**(菜单、拖拽)由调用方注入。

视觉规格:
```
┌─────────────────────────────────────┐
│ ○  • 写周报                      ⋯   │   ○ 完成按钮(borderless)
│       17:00   #周报  ↻               │   • 7px 优先级圆点
└─────────────────────────────────────┘   标题 13 / 元信息 11
   圆角 8pt,controlBackgroundColor 填充
```

接口:

```swift
struct TaskCardView<Trailing: View>: View {
    let task: TodoTask
    let onComplete: () -> Void
    @ViewBuilder var trailing: () -> Trailing
}
```

- **TODO 列表**:在 `trailing` 槽传入 ellipsis `Menu`(推迟到明天/下周、删除)。
- **看板**:`trailing` 传空;在外层卡片上保留 `.contextMenu`(删除)与 `.draggable`。拖拽/落点逻辑仍留在 `BoardView`,卡片视图为纯展示。

元信息行渲染:截止时间(`Theme.deadline`,过期转 `.red`)、`#标签`(`Theme.tag` 绿)、重复图标(`Theme.recurrence`)。

**不纳入** `TaskCardView`:看板归档列的已完成迷你单元(语义不同的、更简单的完成态 cell),保持现状。

## Part 3 — 统一毛玻璃质感

三处面板的承载方式不同(见上文),因此「统一质感」分两路实现,目标都是:卡片坐在毛玻璃材质上、统一圆角与头部内边距。

### 3a. TODO 弹窗(`TaskListView`,MenuBarExtra)

MenuBarExtra `.window` 已由系统绘制毛玻璃 + 圆角,**不动窗口、不自建 NSPanel**。只需让系统材质透出:
- `List` 加 `.scrollContentBackground(.hidden)`,去掉 List 自身的不透明背景,让系统毛玻璃透出。
- 任务行改用 `TaskCardView`,并 `.listRowSeparator(.hidden)`、`.listRowBackground(Color.clear)`、收紧 `listRowInsets`,使卡片像看板卡片一样浮在材质上。
- 头部内边距对齐为 `.horizontal 14 / .vertical 10`,与看板头部一致。
- 保留固定 `360×440` 尺寸与分段头部。
- **不**额外包 `.ultraThinMaterial`:会与系统 vibrancy 叠加发灰。

### 3b. Capture(`PanelController` + `CaptureView`)

让 Capture 外壳成为看板的「兄弟窗口」:无边框、`.ultraThinMaterial`、14pt 圆角。

`PanelController` 改动:
- `styleMask`:`[.titled, .fullSizeContentView, .nonactivatingPanel]` → `[.borderless, .nonactivatingPanel]`,与 `BoardPanelController` 对齐。
- 设 `isOpaque = false`、`backgroundColor = .clear`、`hasShadow = true`,让 SwiftUI 的圆角材质能正确透出(不透明窗口会在圆角背后露出方角)。
- 改用已存在的 `KeyablePanel` 子类(定义于 `BoardPanelController.swift`),使无边框面板仍能成为 key window 以接收 Esc / 文本输入。无需新建类。
- 删除因移除 `.titled` 而失效的孤儿代码:`standardWindowButton(...)` 隐藏三行、`titlebarAppearsTransparent`、`titleVisibility`。`isMovableByWindowBackground`、`delegate`(失焦自动消失)保留。

`CaptureView` 改动:
- 根视图(`.padding(18).frame(width: 560)` 之后)加 `.background(.ultraThinMaterial)` + `.clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))`,与看板一致。

### 3c. 看板

窗口外观维持现状(已是无边框 + `.ultraThinMaterial` + 14pt 圆角)。

## 有意保留的差异(属于正确的 UX,非不一致)

- TODO 弹窗锚定菜单栏;Capture 居中、失焦自动消失;看板底部上滑、常驻。三者职责不同(快速一瞥 / 快速录入 / 工作面板),位置与消失行为有意保留。

## 测试与验证

仅 `Theme` 的纯逻辑(标签文案/颜色映射)有单元测试;视图为纯展示、项目无视图测试设施,故以编译 + 手动验证为准。

1. `Theme` 单元测试:`ThemeTests` 断言 `priorityLabel` / `recurrenceLabel` 文案与 `priority(_:)` 颜色映射,全绿。
2. `xcodebuild` 编译通过,现有单元测试(`BoardStoreTests` / `TodoStoreTests` 等)全绿。
3. 手动:打开 TODO 弹窗 —— 卡片浮在系统毛玻璃上,无不透明 List 底色;卡片样式与看板一致。
4. 手动:打开 Capture —— 无标题栏、毛玻璃 + 14pt 圆角;Esc 取消、⌘↩ 保存、失焦自动消失均正常。
5. 手动:打开看板 —— 卡片外观与 TODO 列表一致;拖拽、完成、删除、归档功能不变。
6. 手动:Capture 标签 chip 为绿色;列表/卡片 `#标签` 为绿色;截止时间为蓝色,三处颜色一致。
7. 代码检查:三个视图中不再存在私有 `priorityColor` / `recurrenceLabel` / `priorityLabel` 副本。
