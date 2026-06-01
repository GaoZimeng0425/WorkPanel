# 设计文档：独立设置面板（Settings Panel）

日期：2026-05-30
分支：feature/todo-app

## 目标

新增一个**独立浮窗式设置面板**，与现有的「捕获」「看板」浮窗风格一致（`PanelController` 浮层），
替代当前藏在菜单栏列表里的 `.sheet` 设置。同时把现有设置项迁移过来，并新增 4 项设置。

## 现状

- 现有 `SettingsView.swift` 是一个 `.sheet`，从 `TaskListView` 的齿轮图标弹出，包含：
  - 捕获快捷键 / 看板快捷键（`KeyboardShortcuts.Recorder`）
  - 开机自启动（`LaunchAtLogin`）
- App 目前**没有任何偏好持久化层**（无 `UserDefaults` / `@AppStorage` / 主题配置）。
  - 快捷键由 `KeyboardShortcuts` 库自行持久化；开机自启由系统持久化。
- 提醒（`ReminderScheduler`）当前在**截止时间精确触发**，无提前量；声音恒为 `.default`。
- `InputParser` 的 `ParsedInput.priority` 默认硬编码为 `.medium`。

## 用户决策（brainstorming 结论）

- 形态：**全新独立浮窗面板**（非菜单栏 sheet，非原生 Settings 窗口）。
- 唤起方式（三个入口）：**专属快捷键** + **菜单栏齿轮按钮** + **看板面板入口**。
- 旧 sheet：**移除**。
- 行为：**屏幕居中 + 手动关闭**（失焦不消失，仅「完成」按钮或 Esc 关闭）。
- 内容：保留现有设置项 + 新增 4 项。
- 新增设置项：提醒提前量、外观主题、通知声音开关、新任务默认优先级。

## 架构决策

### 入口桥接：NotificationCenter 信号

设置面板归属 `AppDelegate`（与捕获/看板一致），但齿轮按钮位于 `MenuBarExtra` 场景中的
`TaskListView`，无法直接引用 `AppDelegate`。

采用统一的 `Notification.Name.openSettings` 信号：齿轮按钮与看板按钮都 `post` 该通知，
`AppDelegate` 注册一次观察者并打开面板。两个入口共用一套机制，完全解耦。

（备选：回调闭包传入 `BoardView` 可行，但 `MenuBarExtra` 齿轮仍需另一种桥接，导致两套机制，故不采用。）

### 持久化：UserDefaults + @AppStorage

`AppSettings` 集中定义键与默认值。SwiftUI 控件用 `@AppStorage` 双向绑定；
非视图消费方（`ReminderScheduler`、`InputParser` 调用处、外观应用）读取相同键。

### 可测试性：参数注入

`ReminderScheduler.schedule` 与 `InputParser.parse` 新增带默认值的参数，由调用方传入设置值，
而非内部直接读取全局 `UserDefaults`。默认值保持现有测试不变。

## 组件设计

### 新增文件

#### `WorkPanel/Store/AppSettings.swift`

- 键常量 + 类型化访问器：
  - `reminderLeadMinutes: Int`（默认 0）
  - `appearance: Appearance`（默认 system）
  - `notificationSound: Bool`（默认 true）
  - `defaultPriority: Priority`（默认 .medium）
- `enum Appearance: String, CaseIterable { case system, light, dark }`
  - `var nsAppearance: NSAppearance?`（system → nil；light → .aqua；dark → .darkAqua）
  - `func apply()` → `NSApp.appearance = nsAppearance`
- 启动时 `UserDefaults.standard.register(defaults:)` 注册默认值（确保 `notificationSound` 默认 true）。

#### `WorkPanel/UI/SettingsPanelController.swift`

- 仿照 `PanelController`（屏幕居中、`.ultraThinMaterial` 由内容提供、`.floating`、无边框 `KeyablePanel`）。
- **不实现** `windowDidResignKey` 自动关闭 → 满足「手动关闭」。
- `show(_:)` / `hide()` / `toggle(_:)`，`isVisible`。
- 复用 `BoardPanelController.swift` 中已有的 `KeyablePanel`。

### 修改文件

#### `WorkPanel/UI/SettingsView.swift`（重写）

- 改为浮窗内容视图：`.padding` + `.background(.ultraThinMaterial)` +
  `.clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))`，宽度约 360–400。
- 入参 `onClose: () -> Void`（取代 `@Environment(\.dismiss)`）。
- `Esc` 与「完成」按钮均调用 `onClose`。
- 分组（`Form` + `Section`）：
  - **快捷键**：捕获 / 看板 / **设置** 三个 `Recorder`
  - **通用**：开机自启动（Toggle）、外观主题（Picker）、新任务默认优先级（Picker）
  - **提醒**：提前量（Picker：0 / 5 / 15 / 30 分钟）、通知声音（Toggle）
- 设置项绑定 `@AppStorage(AppSettings.Key.*)`。外观 Picker 变更后调用 `Appearance.apply()`。

#### `WorkPanel/System/HotkeyManager.swift`

- 新增 `static let toggleSettings = Self("toggleSettings", default: .init(.comma, modifiers: [.command, .option]))`。
- 新增 `static func registerSettings(_ handler:)`。

#### `WorkPanel/WorkPanelApp.swift`（`AppDelegate`）

- 新增 `private let settings = SettingsPanelController()`。
- `applicationDidFinishLaunching`：
  - `AppSettings.registerDefaults()` / `Appearance(...).apply()`（应用启动外观）。
  - `HotkeyManager.registerSettings { ... toggleSettings() }`。
  - 注册 `.openSettings` 观察者 → 打开/切换设置面板。
- `toggleSettings()`：`settings.toggle { SettingsView(onClose: { self.settings.hide() }) }`。
- 捕获流程：`InputParser` 解析时传入 `AppSettings.defaultPriority`；
  调度时传入 `leadMinutes` / `soundEnabled`。

#### `WorkPanel/UI/TaskListView.swift`

- 齿轮按钮改为 `NotificationCenter.default.post(name: .openSettings, object: nil)`。
- 删除 `@State private var showSettings` 与 `.sheet(isPresented:) { SettingsView() }`。

#### `WorkPanel/UI/BoardView.swift`

- 新增齿轮按钮（与 onClose 关闭按钮同区域），`post(.openSettings)`。

#### `WorkPanel/Notifications/ReminderScheduler.swift`

- `schedule(for:now:calendar:leadMinutes:soundEnabled:)`，新增
  `leadMinutes: Int = 0`、`soundEnabled: Bool = true`。
  - 触发时间 = `deadline - leadMinutes*60`；`guard fireDate > now`。
  - `content.sound = soundEnabled ? .default : nil`。

#### `WorkPanel/Parsing/InputParser.swift`

- `parse(_:now:defaultPriority:)`，新增 `defaultPriority: Priority = .medium`。
  - `result.priority` 初值用 `defaultPriority`；遇到 `!高/!中/!低` 等 token 仍覆盖。
- `CaptureView` 经 `@AppStorage` 把设置值传入 `parse`。

## 数据流

- **外观**：启动 + Picker 变更 → `Appearance.apply()` → `NSApp.appearance` → 所有 AppKit 浮窗与 SwiftUI 内容跟随。
- **提醒提前量 / 声音**：捕获保存任务时 `AppDelegate` 读取 `AppSettings` → 传入 `scheduler.schedule(...)`。
- **默认优先级**：`CaptureView` 读取 `@AppStorage` → 传入 `parser.parse(...)` → chip 预览与最终任务一致。
- **打开面板**：齿轮/看板按钮 `post(.openSettings)` 或快捷键 → `AppDelegate` → `SettingsPanelController.toggle`。

## 测试策略

- `ReminderSchedulerTests`：新增用例覆盖 `leadMinutes > 0`（触发时间前移）与 `soundEnabled = false`（`content.sound == nil`）；现有用例因默认参数不变而保持通过。
- `InputParserTests`：新增用例覆盖 `defaultPriority` 注入（无优先级 token 时采用默认值；有 token 时被覆盖）；现有用例保持通过。
- `AppSettings`：可加轻量单测验证默认值与 `Appearance.nsAppearance` 映射。
- 手动验证：三入口均能打开面板；失焦不关闭；Esc/完成关闭；外观切换即时生效；新任务默认优先级与提醒提前量生效。

## 不做（YAGNI）

- 不引入原生 `Settings` 场景（Cmd+, 系统偏好窗口）。
- 不做设置项的导入/导出、同步、重置。
- 不为提前量提供任意自定义分钟输入（仅固定档位）。
