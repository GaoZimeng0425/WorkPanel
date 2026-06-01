# WorkPanel — 快捷键唤起的工作 TODO App 设计

**日期**：2026-05-30
**状态**：设计已确认，待写实现计划
**平台**：macOS 26.5，Swift 6（严格并发），SwiftUI + SwiftData

## 1. 目标

一个常驻菜单栏的轻量工作 TODO 工具。核心诉求是**全局快捷键唤起一个居中浮窗，快速记录工作 TODO**，支持 deadline、优先级、标签、备注，并在截止前提醒。

## 2. 应用形态

- 菜单栏 App：`LSUIElement = YES`，无 Dock 图标、无常规主窗口 scene。
- 两个 UI 界面：
  1. **捕获面板**：全局快捷键唤起的 `NSPanel`，屏幕居中，像 Spotlight。
  2. **菜单栏列表**：点菜单栏图标展开的 `MenuBarExtra(.window)` popover，查看/管理任务。

## 3. 架构与组件

| 组件 | 职责 | 依赖 |
|---|---|---|
| `WorkPanelApp` | App 入口，组装 `MenuBarExtra` scene，注入共享 `ModelContainer` | SwiftUI / SwiftData |
| `PanelController` | 管理捕获面板 `NSPanel` 生命周期：显示/隐藏/居中/抢焦点/失焦关闭 | AppKit |
| `HotkeyManager` | 封装 `KeyboardShortcuts`，把全局热键转成"切换捕获面板"；提供录制 UI | KeyboardShortcuts (SPM) |
| `CaptureView` | 捕获面板的 SwiftUI 视图：标题行 + 解析 chip + 备注 TextArea | SwiftUI |
| `TaskListView` | 菜单栏列表视图：分段切换、标签筛选、行操作、归档入口 | SwiftUI |
| `InputParser` | 纯函数：把一行输入解析成 `ParsedInput(标题, deadline, 优先级, 标签[], 重复)` | 无（纯 Swift，`Sendable`） |
| `TodoStore` | SwiftData 数据访问层：增删改查、归档、重复任务生成、Snooze | SwiftData |
| `ReminderScheduler` | `UserNotifications`：deadline 变化时排/撤到期通知 | UserNotifications |
| `LaunchAtLogin` | `SMAppService` 开机自启开关 | ServiceManagement |

**数据流**：
全局热键 → `PanelController.show` → `CaptureView` 输入 → `InputParser` 实时预览 → `⌘Enter` → `TodoStore.insert` → `ReminderScheduler.schedule` → 面板收起。
`TaskListView` 用 `@Query` 订阅 SwiftData，自动实时刷新。

**Swift 6 并发**：UI 与 SwiftData 操作标 `@MainActor`；`InputParser` 是纯 `Sendable` 函数；`ReminderScheduler` 用 `async`。项目开启 `SWIFT_STRICT_CONCURRENCY = complete`。

## 4. 技术选型（方案 A）

- SwiftUI 为主。
- 全局快捷键：`KeyboardShortcuts`（Sindre Sorhus），自带录制 UI，无需辅助功能权限。**唯一第三方 SPM 依赖。**
- 菜单栏列表：原生 `MenuBarExtra(.window)`。
- 捕获面板：`NSPanel`（borderless、`.floating`、`.nonactivatingPanel`、居中）承载 SwiftUI 视图。
- 开机自启：`SMAppService`。提醒：`UserNotifications`。

## 5. 数据模型

替换模板里的 `Item`：

```swift
@Model final class TodoTask {
    var title: String
    var notes: String          // 备注 / 具体工作内容，默认空
    var deadline: Date?        // 可空
    var priority: Priority     // .high / .medium / .low
    var tags: [String]         // #标签
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var snoozedUntil: Date?    // Snooze：临时移出"今天"
    var recurrence: RecurrenceRule?  // nil = 不重复
}

enum Priority: Int, Codable { case low, medium, high }   // Int 用于排序
enum RecurrenceRule: Codable { case daily, weekdays, weekly, monthly }
```

## 6. 解析语法（InputParser）

一行输入，识别下列 token，剩余文本即标题。解析**实时**进行，结果以 chip 预览，可微调；解析失败的 token 当普通文字保留在标题，**绝不报错挡路**。

| 写法 | 解析为 | 例子 |
|---|---|---|
| `!高` `!中` `!低`（或 `!1`/`!2`/`!3`） | 优先级 | `!高` → high |
| `#词` | 标签（可多个） | `#周报 #客户A` |
| 相对日期：`今天`/`明天`/`后天`/`周一..周日`/`下周X` | deadline 日期 | `明天` |
| 时间：`HH:mm` / `9点` / `下午3点` | deadline 时间 | `17:00`、`下午3点` |
| 重复：`每天`/`每周X`/`每月`/`工作日` | recurrence | `每周一` |

- 日期+时间可组合（`明天 17:00`）；只给时间默认今天；只给日期默认当天 18:00。
- 输入框对识别出的 token 做彩色高亮（日期蓝 / 优先级红 / 标签绿）。

## 7. UI 布局

### 捕获面板（已确认结构）
- 顶部标题行：大号输入框，token 彩色高亮。
- 解析 chip 行：标题 / 截止 / 优先级 / 标签，可 `⇥` 聚焦微调或清除。
- **备注 TextArea**（默认展开）：记录具体工作内容，多行。
- 键盘提示：`⌘Enter` 保存 · `Esc` 取消 · `⇥` 在标题行↔备注间切换。
- 行为：失焦或 `Esc` 关闭；`⌘Enter` 保存并关闭。

### 菜单栏列表（已确认结构）
- 顶部分段：「今天 / 即将到期 / 全部」+ 标签筛选入口。
- 任务行：完成圈 + 优先级圆点（红/橙/灰）+ 标题 + 截止时间（过期标红）+ 标签 chip。
- 底部：「已完成归档」入口 + 「设置」（齿轮）。
- 设置项：自定义快捷键、开机自启开关、通知权限状态。

## 8. 关键行为

- **提醒**：保存且有 deadline 时，`ReminderScheduler` 排一条到期通知（默认到期时刻）。改/删/完成任务时撤销重排。首次使用申请通知权限。
- **重复任务**：勾选完成时，若 `recurrence != nil`，`TodoStore` 按规则生成下一个 occurrence（新 deadline），原任务归档。
- **Snooze**：列表里一键「推到明天/下周」，设 `snoozedUntil`，任务暂时从「今天」视图移走，到点再出现。
- **归档**：`isCompleted = true` 移出主列表，进「已完成」视图，可回看/恢复。
- **排序**：主列表按 优先级 → deadline 排序。

## 9. 权限与打包

- **通知权限**：首次需要排提醒时通过 `UNUserNotificationCenter` 申请。
- **辅助功能权限**：方案 A 的快捷键基于 Carbon（KeyboardShortcuts 封装），**不需要**辅助功能权限。
- **开机自启**：`SMAppService.mainApp.register()`。
- `Info.plist`：`LSUIElement = true`。

## 10. 测试策略

- **`InputParser` 单元测试**（重点）：各 token 组合、中文日期/时间、缺省值、解析失败回退到标题、多标签。
- **`TodoStore` 单元测试**：增删改查、归档、重复任务生成下一 occurrence、Snooze 状态切换。用内存 `ModelContainer`。
- **`ReminderScheduler` 测试**：deadline 变化时排/撤逻辑（mock notification center）。
- UI 交互（面板唤起/键盘流）以手动验证为主。

## 11. v1 范围

**做**：全局快捷键（可自定义）、混合录入 + 实时解析、标题/deadline/优先级/标签/备注、菜单栏列表（今天/即将/全部 + 标签筛选 + 归档）、截止提醒、重复任务、Snooze、开机自启、本地持久化。

**不做**：iCloud / 多设备同步、子任务层级、协作共享、日历集成、提前 X 分钟提醒（后续可加）。
