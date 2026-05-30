# 独立设置面板 (Settings Panel) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一个独立浮窗式设置面板（居中、失焦不关闭、手动关闭），替代旧的菜单栏 sheet，迁移现有设置项并新增 4 项设置（提醒提前量、外观主题、通知声音、新任务默认优先级）。

**Architecture:** 新增 `AppSettings`（UserDefaults 持久化层）+ `SettingsPanelController`（仿 `PanelController` 但无失焦自动关闭）。`SettingsView` 重写为浮窗内容视图，控件用 `@AppStorage` 绑定。三个入口（专属快捷键、菜单栏齿轮、看板齿轮）经 `Notification.Name.openSettings` 统一通知 `AppDelegate` 打开面板。`ReminderScheduler.schedule` 与 `InputParser.parse` 新增带默认值参数；调度参数默认值直接取自 `AppSettings`，使全部调用点零改动即自动生效，测试可显式覆盖。

**Tech Stack:** Swift / SwiftUI / AppKit (NSPanel) / SwiftData / KeyboardShortcuts 库 / Swift Testing 框架 (`@Test` / `#expect`)。

**Build/Test commands:**
- 构建：`xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
- 全量测试：`xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet`
- 单类测试：追加 `-only-testing:WorkPanelTests/<ClassName>`

> ⚠️ 新增的 `.swift` 文件需加入 Xcode 工程的 target（`project.pbxproj`）。若构建报 "cannot find type"，多半是文件未加入 `WorkPanel` target。可在 Xcode 中拖入，或用 `xcodebuild` 前确认 pbxproj 已含该文件引用。

---

## File Structure

**新增：**
- `WorkPanel/Store/AppSettings.swift` — UserDefaults 键/访问器 + `Appearance` 枚举（含 NSAppearance 映射与 `apply()`）。
- `WorkPanel/UI/SettingsPanelController.swift` — 居中浮窗控制器（无失焦自动关闭）+ `Notification.Name.openSettings`。

**修改：**
- `WorkPanel/Parsing/InputParser.swift` — `parse` 增 `defaultPriority` 参数。
- `WorkPanel/Notifications/ReminderScheduler.swift` — `schedule` 增 `leadMinutes` / `soundEnabled` 参数。
- `WorkPanel/System/HotkeyManager.swift` — 增 `.toggleSettings` 快捷键 + `registerSettings`。
- `WorkPanel/UI/SettingsView.swift` — 重写为浮窗内容视图。
- `WorkPanel/WorkPanelApp.swift` — `AppDelegate` 接线（控制器、快捷键、通知观察、启动应用外观、注册默认值）。
- `WorkPanel/UI/TaskListView.swift` — 齿轮按钮改为发通知；移除 sheet。
- `WorkPanel/UI/BoardView.swift` — 增设置齿轮按钮；快速新建用默认优先级。
- `WorkPanel/UI/CaptureView.swift` — 解析时传入默认优先级。

**测试：**
- `WorkPanelTests/AppSettingsTests.swift`（新增）
- `WorkPanelTests/InputParserTests.swift`（追加用例）
- `WorkPanelTests/ReminderSchedulerTests.swift`（追加用例）

---

## Task 1: AppSettings 持久化层 + Appearance 枚举

**Files:**
- Create: `WorkPanel/Store/AppSettings.swift`
- Test: `WorkPanelTests/AppSettingsTests.swift`

- [ ] **Step 1: 写失败测试**

`WorkPanelTests/AppSettingsTests.swift`：

```swift
import Testing
import AppKit
@testable import WorkPanel

@MainActor
struct AppSettingsTests {
    @Test func appearanceMapsToNSAppearance() {
        #expect(Appearance.system.nsAppearance == nil)
        #expect(Appearance.light.nsAppearance?.name == .aqua)
        #expect(Appearance.dark.nsAppearance?.name == .darkAqua)
    }

    @Test func appearanceHasLabelForEveryCase() {
        for a in Appearance.allCases {
            #expect(!a.label.isEmpty)
        }
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet -only-testing:WorkPanelTests/AppSettingsTests`
Expected: FAIL（编译错误 "cannot find 'Appearance'"）。

- [ ] **Step 3: 实现 AppSettings.swift**

`WorkPanel/Store/AppSettings.swift`：

```swift
import AppKit

/// 全 App 的偏好持久化层。键集中定义,SwiftUI 控件用 @AppStorage 绑定相同键,
/// 非视图消费方读取这里的类型化访问器。
enum AppSettings {
    enum Key {
        static let reminderLeadMinutes = "reminderLeadMinutes"
        static let appearance = "appearance"
        static let notificationSound = "notificationSound"
        static let defaultPriority = "defaultPriority"
    }

    /// 在 App 启动时调用一次,确保未设置过的项使用正确默认值(尤其 notificationSound 默认 true)。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.reminderLeadMinutes: 0,
            Key.appearance: Appearance.system.rawValue,
            Key.notificationSound: true,
            Key.defaultPriority: Priority.medium.rawValue,
        ])
    }

    static var reminderLeadMinutes: Int {
        UserDefaults.standard.integer(forKey: Key.reminderLeadMinutes)
    }
    static var notificationSound: Bool {
        UserDefaults.standard.bool(forKey: Key.notificationSound)
    }
    static var defaultPriority: Priority {
        Priority(rawValue: UserDefaults.standard.integer(forKey: Key.defaultPriority)) ?? .medium
    }
    static var appearance: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: Key.appearance) ?? "") ?? .system
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light:  "浅色"
        case .dark:   "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    /// 应用到整个 App(所有 AppKit 浮窗与其内嵌 SwiftUI 内容均跟随)。
    @MainActor func apply() {
        NSApp.appearance = nsAppearance
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet -only-testing:WorkPanelTests/AppSettingsTests`
Expected: PASS（2 个用例通过）。

> 注：`AppSettings` 的 UserDefaults 访问器依赖全局 `.standard`,不做独立单测(会受全局状态干扰),其行为由下游 Task 2/3 的参数化测试与构建覆盖。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/AppSettings.swift WorkPanelTests/AppSettingsTests.swift
git commit -m "feat: add AppSettings preferences layer + Appearance enum"
```

---

## Task 2: InputParser 默认优先级参数

**Files:**
- Modify: `WorkPanel/Parsing/InputParser.swift:30`（`parse` 签名与初值）
- Test: `WorkPanelTests/InputParserTests.swift`（追加 2 用例）

- [ ] **Step 1: 追加失败测试**

在 `WorkPanelTests/InputParserTests.swift` 的 `unrecognizedTokensStayInTitle` 用例后、闭合大括号前追加：

```swift
    @Test func defaultPriorityAppliesWhenNoToken() {
        let r = InputParser(calendar: calendar).parse("写周报", now: now, defaultPriority: .high)
        #expect(r.priority == .high)
    }

    @Test func priorityTokenOverridesDefault() {
        let r = InputParser(calendar: calendar).parse("写周报 !低", now: now, defaultPriority: .high)
        #expect(r.priority == .low)
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet -only-testing:WorkPanelTests/InputParserTests`
Expected: FAIL（编译错误：`parse` 无 `defaultPriority` 参数）。

- [ ] **Step 3: 修改 parse 签名与初值**

`WorkPanel/Parsing/InputParser.swift`，将第 30 行起的函数签名与首行改为：

```swift
    nonisolated func parse(_ input: String, now: Date, defaultPriority: Priority = .medium) -> ParsedInput {
        var result = ParsedInput()
        result.priority = defaultPriority
        var titleWords: [String] = []
```

（即在 `var result = ParsedInput()` 之后、`var titleWords` 之前插入 `result.priority = defaultPriority`，并给签名加 `defaultPriority: Priority = .medium` 参数。`priorityMap` 命中时仍会覆盖 `result.priority`，无需改动循环体。）

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet -only-testing:WorkPanelTests/InputParserTests`
Expected: PASS（含原有用例 + 2 新用例；`plainTitleHasNoMetadata` 因默认参数 `.medium` 仍通过）。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Parsing/InputParser.swift WorkPanelTests/InputParserTests.swift
git commit -m "feat: InputParser.parse accepts defaultPriority"
```

---

## Task 3: ReminderScheduler 提前量 + 声音参数

**Files:**
- Modify: `WorkPanel/Notifications/ReminderScheduler.swift:24-39`
- Test: `WorkPanelTests/ReminderSchedulerTests.swift`（追加 2 用例）

- [ ] **Step 1: 追加失败测试**

在 `WorkPanelTests/ReminderSchedulerTests.swift` 的 `cancelRemovesByIdentifier` 用例后、闭合大括号前追加：

```swift
    @Test func leadTimeBeyondDeadlineSkips() async {
        let mock = MockCenter()
        let scheduler = ReminderScheduler(center: mock)
        let now = Date()
        // 截止 10 分钟后,但提前 15 分钟提醒 → 触发时间已过 → 跳过
        let task = TodoTask(title: "x", deadline: now.addingTimeInterval(600))
        await scheduler.schedule(for: task, now: now, leadMinutes: 15)
        #expect(mock.added.isEmpty)
    }

    @Test func soundDisabledLeavesNilSound() async {
        let mock = MockCenter()
        let scheduler = ReminderScheduler(center: mock)
        let now = Date()
        let task = TodoTask(title: "x", deadline: now.addingTimeInterval(3600))
        await scheduler.schedule(for: task, now: now, soundEnabled: false)
        #expect(mock.added.count == 1)
        #expect(mock.added.first?.content.sound == nil)
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet -only-testing:WorkPanelTests/ReminderSchedulerTests`
Expected: FAIL（编译错误：`schedule` 无 `leadMinutes` / `soundEnabled` 参数）。

- [ ] **Step 3: 修改 schedule 实现**

`WorkPanel/Notifications/ReminderScheduler.swift`，将 `schedule(for:now:calendar:)` 整个方法（第 24–39 行）替换为：

```swift
    func schedule(for task: TodoTask,
                  now: Date = .now,
                  calendar: Calendar = .current,
                  leadMinutes: Int = AppSettings.reminderLeadMinutes,
                  soundEnabled: Bool = AppSettings.notificationSound) async {
        cancel(for: task)
        guard let deadline = task.deadline, !task.isCompleted else { return }
        let fireDate = deadline.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes.isEmpty ? "任务到期" : task.notes
        content.sound = soundEnabled ? .default : nil

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString,
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }
```

> 说明：`leadMinutes` / `soundEnabled` 默认值直接取自 `AppSettings`,在**调用时**求值。因此 capture / 列表完成 / 看板完成 / 看板快速新建 这 4 个 `scheduler.schedule(...)` 调用点**无需改动**即自动按当前设置生效;测试则显式传参覆盖。原 `deadline > now` 守卫被 `fireDate > now` 取代(leadMinutes 默认 0 时等价)。

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet -only-testing:WorkPanelTests/ReminderSchedulerTests`
Expected: PASS（原 3 用例 + 2 新用例。`schedulesFutureDeadline` 中 `leadMinutes` 默认取 `AppSettings`=0,`fireDate`=deadline>now 仍调度通过）。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Notifications/ReminderScheduler.swift WorkPanelTests/ReminderSchedulerTests.swift
git commit -m "feat: ReminderScheduler honors lead time and sound setting"
```

---

## Task 4: 设置面板快捷键

**Files:**
- Modify: `WorkPanel/System/HotkeyManager.swift`

- [ ] **Step 1: 增加快捷键定义与注册函数**

`WorkPanel/System/HotkeyManager.swift`，在 `toggleBoard` 定义后（第 12 行后）追加到 `extension` 内：

```swift
    static let toggleSettings = Self(
        "toggleSettings",
        default: .init(.comma, modifiers: [.command, .option])
    )
```

并在 `enum HotkeyManager` 内 `registerBoard` 之后追加：

```swift
    static func registerSettings(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleSettings, action: handler)
    }
```

- [ ] **Step 2: 构建确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/System/HotkeyManager.swift
git commit -m "feat: add toggleSettings hotkey (cmd+opt+,)"
```

---

## Task 5: SettingsPanelController + openSettings 通知

**Files:**
- Create: `WorkPanel/UI/SettingsPanelController.swift`

- [ ] **Step 1: 创建控制器**

`WorkPanel/UI/SettingsPanelController.swift`：

```swift
import AppKit
import SwiftUI

extension Notification.Name {
    /// 任一入口(菜单栏齿轮 / 看板齿轮)请求打开设置面板。
    static let openSettings = Notification.Name("openSettings")
}

/// 居中浮窗设置面板。仿 PanelController,但**失焦不自动关闭**(手动关闭:完成按钮 / Esc)。
@MainActor
final class SettingsPanelController {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content())
        positionCentered(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle<Content: View>(@ViewBuilder _ content: () -> Content) {
        if isVisible { hide() } else { show(content) }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionCentered(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 + visible.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

> `KeyablePanel` 已在 `WorkPanel/UI/BoardPanelController.swift:5` 定义,此处复用,不重复声明。

- [ ] **Step 2: 构建确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/SettingsPanelController.swift
git commit -m "feat: add SettingsPanelController (centered, no blur-dismiss)"
```

---

## Task 6: TaskListView 齿轮改为发通知并移除 sheet

> 先于 SettingsView 重写,使其不再有旧式 `SettingsView()` 调用点,后续重写不会破坏构建。

**Files:**
- Modify: `WorkPanel/UI/TaskListView.swift:16,50,135`

- [ ] **Step 1: 移除 showSettings 状态**

删除第 16 行：

```swift
    @State private var showSettings = false
```

- [ ] **Step 2: 移除 sheet**

删除第 50 行：

```swift
        .sheet(isPresented: $showSettings) { SettingsView() }
```

（删除后 `body` 的 `.frame(width: 360, height: 440)` 成为该 `VStack` 的最后一个修饰符。）

- [ ] **Step 3: 齿轮按钮改为发通知**

将第 135 行：

```swift
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
```

替换为：

```swift
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: { Image(systemName: "gearshape") }
```

- [ ] **Step 4: 构建确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED（旧 `SettingsView()` 调用点已移除；`.openSettings` 由 Task 5 定义）。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/TaskListView.swift
git commit -m "feat: menu-bar gear opens settings panel via notification"
```

---

## Task 7: 重写 SettingsView 为浮窗内容视图

**Files:**
- Modify: `WorkPanel/UI/SettingsView.swift`（整文件替换）

- [ ] **Step 1: 整文件替换**

`WorkPanel/UI/SettingsView.swift`：

```swift
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    let onClose: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(AppSettings.Key.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(AppSettings.Key.defaultPriority) private var defaultPriority = Priority.medium.rawValue
    @AppStorage(AppSettings.Key.reminderLeadMinutes) private var leadMinutes = 0
    @AppStorage(AppSettings.Key.notificationSound) private var sound = true

    private let leadOptions = [0, 5, 15, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置").font(.headline)

            Form {
                Section("快捷键") {
                    KeyboardShortcuts.Recorder("唤起捕获面板：", name: .toggleCapture)
                    KeyboardShortcuts.Recorder("唤起看板面板：", name: .toggleBoard)
                    KeyboardShortcuts.Recorder("唤起设置面板：", name: .toggleSettings)
                }

                Section("通用") {
                    Toggle("开机自启动", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do { try LaunchAtLogin.setEnabled(enabled) }
                            catch { launchAtLogin = LaunchAtLogin.isEnabled }
                        }
                    Picker("外观主题", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: appearance) { _, raw in
                        (Appearance(rawValue: raw) ?? .system).apply()
                    }
                    Picker("新任务默认优先级", selection: $defaultPriority) {
                        Text("高").tag(Priority.high.rawValue)
                        Text("中").tag(Priority.medium.rawValue)
                        Text("低").tag(Priority.low.rawValue)
                    }
                }

                Section("提醒") {
                    Picker("提前提醒", selection: $leadMinutes) {
                        ForEach(leadOptions, id: \.self) { m in
                            Text(m == 0 ? "准时" : "\(m) 分钟前").tag(m)
                        }
                    }
                    Toggle("通知声音", isOn: $sound)
                }
            }

            HStack {
                Spacer()
                Button("完成") { onClose() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}
```

> `@AppStorage(AppSettings.Key.appearance)` 存 String(`Appearance.rawValue`),`defaultPriority` / `leadMinutes` 存 Int,`sound` 存 Bool —— 均为 @AppStorage 原生支持类型。优先级 Picker 的 `.tag` 用 `Priority.*.rawValue`(Int),与 selection 类型一致。

- [ ] **Step 2: 构建确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED（Task 6 已移除旧 `SettingsView()` 调用点,新 `SettingsView` 此刻无调用者,自身合法即可编译；调用者在 Task 8 加入）。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/SettingsView.swift
git commit -m "feat: rewrite SettingsView as frosted panel content with new settings"
```

---

## Task 8: AppDelegate 接线

**Files:**
- Modify: `WorkPanel/WorkPanelApp.swift`

- [ ] **Step 1: 增加设置控制器属性**

在 `AppDelegate` 内（`WorkPanel/WorkPanelApp.swift:31-33` 的属性区）追加：

```swift
    private let settings = SettingsPanelController()
```

- [ ] **Step 2: 在 applicationDidFinishLaunching 接线**

将 `applicationDidFinishLaunching`（第 35–39 行）整体替换为：

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        AppSettings.appearance.apply()
        HotkeyManager.register { [weak self] in self?.toggleCapture() }
        HotkeyManager.registerBoard { [weak self] in self?.toggleBoard() }
        HotkeyManager.registerSettings { [weak self] in self?.toggleSettings() }
        NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.toggleSettings() }
        }
        Task { _ = await scheduler.requestAuthorization() }
    }
```

- [ ] **Step 3: 增加 toggleSettings 方法**

在 `toggleBoard()` 方法（第 60–66 行）之后追加：

```swift
    private func toggleSettings() {
        settings.toggle {
            SettingsView(onClose: { [weak self] in self?.settings.hide() })
        }
    }
```

- [ ] **Step 4: 构建确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED（`SettingsView(onClose:)` 调用者就位，全部消解）。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/WorkPanelApp.swift
git commit -m "feat: wire settings panel into AppDelegate (hotkey, notification, appearance)"
```

---

## Task 9: BoardView 设置入口 + 快速新建用默认优先级

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift:79-87,124-137`

- [ ] **Step 1: header 增加设置齿轮按钮**

将 `header`（第 79–87 行）替换为：

```swift
    private var header: some View {
        HStack {
            Text("看板").font(.headline)
            Text("\(tasks.filter { !$0.isCompleted }.count) 项").foregroundStyle(.secondary).font(.caption)
            Spacer()
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            Text("esc 收起").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
```

- [ ] **Step 2: 快速新建解析时传默认优先级**

将 `addTaskField` 中第 126 行：

```swift
            let parsed = InputParser().parse(title, now: .now)
```

替换为：

```swift
            let parsed = InputParser().parse(title, now: .now, defaultPriority: AppSettings.defaultPriority)
```

- [ ] **Step 3: 构建确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat: board gear opens settings; quick-add uses default priority"
```

---

## Task 10: CaptureView 解析用默认优先级

**Files:**
- Modify: `WorkPanel/UI/CaptureView.swift:7-14`

- [ ] **Step 1: 增加 @AppStorage 并在解析时传入**

在 `CaptureView` 的 `@State private var notes = ""`（第 8 行）之后追加：

```swift
    @AppStorage(AppSettings.Key.defaultPriority) private var defaultPriority = Priority.medium.rawValue
```

并将 `parsed` 计算属性（第 14 行）：

```swift
    private var parsed: ParsedInput { parser.parse(input, now: .now) }
```

替换为：

```swift
    private var parsed: ParsedInput {
        parser.parse(input, now: .now, defaultPriority: Priority(rawValue: defaultPriority) ?? .medium)
    }
```

> 顶部已 `import SwiftUI`,`@AppStorage` 无需额外 import。

- [ ] **Step 2: 构建确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 全量测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -quiet`
Expected: 全部测试 PASS。

- [ ] **Step 4: 提交**

```bash
git add WorkPanel/UI/CaptureView.swift
git commit -m "feat: capture preview uses default priority setting"
```

---

## 最终手动验证（实现完成后）

构建运行 App，逐项确认：

- [ ] 三入口均能打开设置面板：① 快捷键 ⌘⌥, ② 菜单栏列表底部齿轮 ③ 看板顶部齿轮。
- [ ] 面板屏幕居中；点击面板外部/切换 App **不**自动关闭。
- [ ] 「完成」按钮与 Esc 均可关闭。
- [ ] 切换「外观主题」（浅色/深色/跟随系统）即时生效于所有浮窗。
- [ ] 设置「新任务默认优先级=高」后，在 Capture 输入无 `!` 优先级的任务，chip 预览与保存后任务均为「高」；看板快速新建同理。
- [ ] 设置「提前提醒=15 分钟前」后，新任务的本地通知在截止前 15 分钟触发（可设近端截止时间验证）。
- [ ] 关闭「通知声音」后，提醒无声音。
- [ ] 旧的菜单栏 sheet 已不存在（齿轮直接打开新浮窗）。

> 完成后建议调用 superpowers:requesting-code-review 做一次评审。
