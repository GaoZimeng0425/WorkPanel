# 看板宽度可设置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把看板面板写死的 `visible.width * 0.8` 改为「设置 → 通用 → 看板宽度」的百分比滑块（50%–100%，步进 5%，默认 80%），改动即时作用到已打开的面板。

**Architecture:** 百分比存 `UserDefaults`（`boardWidthPercent`，Double），读取侧统一夹取 0.5...1.0 并兜底 NaN。`BoardPanelController` 用一个纯函数 `boardFrame(...)` 由可见屏、高度、百分比、最小像素宽算出居中贴底的 frame；`show()` 与「设置改动」通知共用它。设置面板只写默认值并投递 `.boardWidthChanged`，`AppDelegate` 按现有模式转给 `board.applyWidth()`。不做鼠标拖拽宽度。

**Tech Stack:** Swift / AppKit (`NSPanel`) / SwiftUI (`@AppStorage`, `Slider`) / Swift Testing / UserDefaults。

**Spec:** 无独立 spec 文件；本计划的规格来自对话裁决：宽度放设置、滑块 50–100%、默认 80%、最小像素宽兜底、改动即时生效；高度维持现有拖拽。

## Global Constraints

- 默认 80%，范围 50%–100%，步进 5%；存储为比例 Double（0.5–1.0），不存像素。
- 宽度始终按当前屏幕 `visibleFrame.width` 计算，保持水平居中、底边距 `visibleFrame.minY + 16`（沿用 `margin = 16`）。
- 最小像素宽 `760`，但仍不得超过 `visibleFrame.width`。
- 只有面板可见时才应用新宽度；不可见时只落库，不得顺带弹出面板。
- 测试只跑单元包，禁止 e2e/UI 测试：
  `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`
- 文案、图标、注释风格跟随 `SettingsView` 现有行；注释解释「为什么」，不写「做什么」。

## Review Focus

1. 接投影/小屏时 `visibleFrame.width < 760`：最小宽必须退让到屏幕宽，否则面板超出屏幕、左右边缘不可见。
2. `defaults write` 写入的越界或损坏值（`0`、`1.5`、`NaN`）：必须回落/夹取到 0.5–1.0，NaN 直通 `NSRect` 会崩。
3. 面板不可见时拖动设置滑块：只落库，不能恢复显示面板或改 `currentHeight`（`applyWidth()` 的 `isVisible` 早退；依赖 AppKit 面板生命周期，无单测，收尾人工确认）。
4. 看板在副屏而设置面板在主屏：改动应作用于看板所在屏（`panel.screen`），不是 `NSScreen.main`（同上，多屏无单测，收尾人工确认）。
5. 高度接近上限时改宽度：高度与底部间距必须保持不变，只改宽度与 x。

---

### Task 1: AppSettings 存取看板宽度百分比

**Files:**
- Modify: `WorkPanel/Store/AppSettings.swift:21-63`（默认值常量、`Key`、`registerDefaults`）
- Test: `WorkPanelTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: 无（首个任务）。
- Produces:
  - `AppSettings.Key.boardWidthPercent: String`
  - `AppSettings.defaultBoardWidthPercent: Double = 0.8`
  - `AppSettings.boardWidthPercentRange: ClosedRange<Double> = 0.5...1.0`
  - `AppSettings.boardWidthPercent: Double`（读取时夹取，NaN/非有限值回落默认）

- [x] **Step 1: 写失败测试**

在 `AppSettingsTests` 追加（套件已 `@Suite(.serialized)`，用 `defer` 清键）：

```swift
@Test func boardWidthDefaultsTo80Percent() {
    defer { AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardWidthPercent) }
    AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardWidthPercent)
    #expect(AppSettings.boardWidthPercent == 0.8)
}

@Test func boardWidthClampsToValidRange() {
    defer { AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardWidthPercent) }
    for (stored, expected) in [(0.3, 0.5), (1.8, 1.0)] {
        AppSettings.defaults.set(stored, forKey: AppSettings.Key.boardWidthPercent)
        #expect(AppSettings.boardWidthPercent == expected)
    }
}

@Test func boardWidthNonFiniteFallsBackToDefault() {
    defer { AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardWidthPercent) }
    AppSettings.defaults.set(Double.nan, forKey: AppSettings.Key.boardWidthPercent)
    #expect(AppSettings.boardWidthPercent == 0.8)
}

@Test func boardWidthPersistsValidValue() {
    defer { AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardWidthPercent) }
    AppSettings.defaults.set(0.65, forKey: AppSettings.Key.boardWidthPercent)
    #expect(AppSettings.boardWidthPercent == 0.65)
}
```

- [x] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AppSettingsTests CODE_SIGNING_ALLOWED=NO`
Expected: 编译失败，`AppSettings.Key.boardWidthPercent` / `boardWidthPercent` 不存在。

- [x] **Step 3: 实现键、默认值与夹取读取**

`AppSettings` 内，在 `defaultMCPPort` 旁加常量；`Key` 里 `boardHeight` 下方加键；`registerDefaults` 里注册默认值；getter 放在 `boardHeight` 之后：

```swift
static let defaultBoardWidthPercent = 0.8
/// 滑块的取值范围,读取侧与 UI 共用同一决策点。
static let boardWidthPercentRange: ClosedRange<Double> = 0.5...1.0

// Key 内:
static let boardWidthPercent = "boardWidthPercent"   // Double: 看板宽度占可见屏宽比例,0.8 默认

// registerDefaults 内:
Key.boardWidthPercent: defaultBoardWidthPercent,

// getter:
/// 夹取在读取侧兜底:defaults 可能被外部写入越界值;NaN 若直通 NSRect 会崩。
static var boardWidthPercent: Double {
    let p = defaults.double(forKey: Key.boardWidthPercent)
    guard p.isFinite, p > 0 else { return defaultBoardWidthPercent }
    return Swift.min(Swift.max(p, boardWidthPercentRange.lowerBound), boardWidthPercentRange.upperBound)
}
```

- [x] **Step 4: 跑测试确认通过**

Run: 同 Step 2
Expected: PASS（4 个新用例 + 原有用例全绿）。

- [x] **Step 5: 提交**

```bash
git add WorkPanel/Store/AppSettings.swift WorkPanelTests/AppSettingsTests.swift
git commit -m "feat(settings): persist board width percent with clamped default"
```

---

### Task 2: BoardPanelController 按百分比计算并应用宽度

**Files:**
- Modify: `WorkPanel/UI/Panels/BoardPanelController.swift`（frame 计算、`show()`、新增 `applyWidth()`、通知名）
- Modify: `WorkPanel/WorkPanelApp.swift:77-91`（观察 `.boardWidthChanged`）
- Test: `WorkPanelTests/BoardPanelControllerTests.swift`

**Interfaces:**
- Consumes: `AppSettings.boardWidthPercent`（Task 1）。
- Produces:
  - `BoardPanelController.minWidth: CGFloat = 760`（实例常量）
  - `BoardPanelController.boardFrame(visible: NSRect, height: CGFloat, percent: Double, minWidth: CGFloat, margin: CGFloat) -> NSRect`（`nonisolated static`，纯函数）
  - `BoardPanelController.applyWidth()`
  - `Notification.Name.boardWidthChanged`

- [x] **Step 1: 写失败测试**

在 `BoardPanelControllerTests` 追加：

```swift
// 80% 居中贴底:1600 宽屏 → 1280 宽、x=160、底边 +16。
@Test func boardFrameUsesPercentAndCenters() {
    let visible = NSRect(x: 0, y: 0, width: 1600, height: 900)
    let frame = BoardPanelController.boardFrame(visible: visible, height: 500,
                                                percent: 0.8, minWidth: 760, margin: 16)
    #expect(frame.width == 1280)
    #expect(frame.origin.x == 160)
    #expect(frame.origin.y == 16)
    #expect(frame.height == 500)
}

// 百分比算出来比 760 窄 → 用最小宽,仍居中。
@Test func boardFrameFloorsAtMinWidth() {
    let visible = NSRect(x: 0, y: 0, width: 1200, height: 900)
    let frame = BoardPanelController.boardFrame(visible: visible, height: 500,
                                                percent: 0.5, minWidth: 760, margin: 16)
    #expect(frame.width == 760)
    #expect(frame.origin.x == 220)
}

// 小屏(宽 700)连最小宽都放不下 → 退让到屏宽,x=0,不得越界。
@Test func boardFrameNeverExceedsVisibleWidth() {
    let visible = NSRect(x: 100, y: 40, width: 700, height: 600)
    let frame = BoardPanelController.boardFrame(visible: visible, height: 420,
                                                percent: 0.5, minWidth: 760, margin: 16)
    #expect(frame.width == 700)
    #expect(frame.origin.x == 100)
    #expect(frame.origin.y == 56)
}
```

- [x] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:WorkPanelTests/BoardPanelControllerTests CODE_SIGNING_ALLOWED=NO`
Expected: 编译失败，`boardFrame` 不存在。

- [x] **Step 3: 实现纯函数、改 `show()`、加 `applyWidth()` 与通知**

在 `BoardPanelController` 内：

```swift
/// 看板最小像素宽:再窄列会挤到只能横向滚动,失去一屏总览的意义。
private let minWidth: CGFloat = 760

/// 由可见屏、高度、宽度百分比算面板 frame:水平居中、底边固定 margin。
/// 百分比夹取与最小宽都在这里收口,便于无屏幕环境单测。
nonisolated static func boardFrame(visible: NSRect, height: CGFloat, percent: Double,
                                   minWidth: CGFloat, margin: CGFloat) -> NSRect {
    let proposed = visible.width * CGFloat(percent)
    let width = Swift.min(Swift.max(proposed, minWidth), visible.width)
    return NSRect(x: visible.midX - width / 2, y: visible.minY + margin,
                  width: width, height: height)
}
```

`show()` 里把写死宽度的两行（`let width = visible.width * 0.8` 与 `let final = NSRect(...)`）换成：

```swift
let final = Self.boardFrame(visible: visible, height: currentHeight,
                            percent: AppSettings.boardWidthPercent,
                            minWidth: minWidth, margin: margin)
```

新增：

```swift
/// 设置里改了宽度且面板可见时即时套用:只改 frame,不碰高度/动画,滑块拖动才跟手。
/// 屏幕取面板当前所在屏(副屏打开看板时以副屏为准),而不是 NSScreen.main。
func applyWidth() {
    guard let panel, panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
    panel.setFrame(Self.boardFrame(visible: screen.visibleFrame, height: panel.frame.height,
                                   percent: AppSettings.boardWidthPercent,
                                   minWidth: minWidth, margin: margin),
                   display: true)
}
```

本文件顶部（`KeyablePanel` 前）加通知名：

```swift
extension Notification.Name {
    /// 设置里看板宽度变化:AppDelegate 转给 board.applyWidth()。
    static let boardWidthChanged = Notification.Name("boardWidthChanged")
}
```

`AppDelegate.applicationDidFinishLaunching` 里，仿 `.mcpSettingsChanged` 加：

```swift
NotificationCenter.default.addObserver(forName: .boardWidthChanged, object: nil, queue: .main) { [weak self] _ in
    MainActor.assumeIsolated { self?.board.applyWidth() }
}
```

- [x] **Step 4: 跑测试与构建确认通过**

Run: `xcodebuild test ... -only-testing:WorkPanelTests/BoardPanelControllerTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS（3 个新用例 + 原有 clamp/resize 用例全绿）。

- [x] **Step 5: 提交**

```bash
git add WorkPanel/UI/Panels/BoardPanelController.swift WorkPanel/WorkPanelApp.swift WorkPanelTests/BoardPanelControllerTests.swift
git commit -m "feat(board): derive panel width from configured percent"
```

---

### Task 3: 设置面板加「看板宽度」滑块

**Files:**
- Modify: `WorkPanel/UI/Settings/SettingsView.swift`（`@AppStorage` 属性、`generalSection` 新行）

**Interfaces:**
- Consumes: `AppSettings.Key.boardWidthPercent`、`AppSettings.boardWidthPercentRange`、`AppSettings.defaultBoardWidthPercent`（Task 1）；`Notification.Name.boardWidthChanged`（Task 2）。
- Produces: 无（UI 终端）。

- [x] **Step 1: 加绑定属性**

在 `@AppStorage(AI…)` 之前、`defaultPriority` 之后：

```swift
@AppStorage(AppSettings.Key.boardWidthPercent) private var boardWidthPercent = AppSettings.defaultBoardWidthPercent
```

- [x] **Step 2: 在 `generalSection` 加行**

放在「外观主题」与「新任务默认优先级」之间，含 `divider`：

```swift
divider
row("看板宽度", systemImage: "arrow.left.and.right") {
    HStack(spacing: 8) {
        Slider(value: $boardWidthPercent,
               in: AppSettings.boardWidthPercentRange,
               step: 0.05)
            .frame(width: 150)
        Text("\(Int((boardWidthPercent * 100).rounded()))%")
            .font(.callout.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 42, alignment: .trailing)
    }
    .onChange(of: boardWidthPercent) { _, _ in
        NotificationCenter.default.post(name: .boardWidthChanged, object: nil)
    }
}
```

- [x] **Step 3: 构建 + 跑单元包**

说明：此行是纯 SwiftUI 视图接线，仓库对此类视图无单测；逻辑已由 Task 1/2 覆盖，本条以构建与全量单元包为准。

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED，全部单元测试 PASS。

- [x] **Step 4: 提交**

```bash
git add WorkPanel/UI/Settings/SettingsView.swift
git commit -m "feat(settings): add board width slider"
```

---

## 手动验收（交给用户）

1. 打开设置 → 通用：拖动「看板宽度」，数值标签同步变化；看板已打开时应实时变宽/变窄，高度与底部间距不变。
2. 关掉看板改宽度，再打开看板：宽度生效。
3. 小屏或缩小窗口场景：宽度不会小于可用内容的合理宽度，也不会超出屏幕。
