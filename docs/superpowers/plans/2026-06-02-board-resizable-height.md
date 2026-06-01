# 看板可拉伸高度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让看板浮层可从顶部把手向上拉伸,在最小 360 与屏幕可用高度之间自由调节,并在重启后记住高度。

**Architecture:** `BoardPanelController` 作为高度唯一真值来源,持久化到 `UserDefaults`,`show()` 时夹紧到屏幕范围。`BoardView` 顶部放一个胶囊把手,`DragGesture` 把竖直位移经闭包回传给 controller,controller 实时改 panel 高度(底边锚定不动),松手时写回偏好。

**Tech Stack:** Swift / SwiftUI / AppKit (`NSPanel`) / SwiftData;测试用 Swift Testing(`@Test`/`#expect`),通过 `xcodebuild`。

---

## File Structure

- `WorkPanel/Store/AppSettings.swift` — 修改:新增 `boardHeight` 键与类型化访问器。
- `WorkPanel/UI/BoardPanelController.swift` — 修改:用 `currentHeight` 替换固定 `height`,新增 `minHeight`/`maxHeight(for:)`/`clampHeight(_:min:max:)`/`resize(translationY:)`/`endResize()`。
- `WorkPanel/UI/BoardView.swift` — 修改:新增两个 resize 闭包参数与顶部胶囊把手。
- `WorkPanel/WorkPanelApp.swift` — 修改:`toggleBoard()` 构造 `BoardView` 时接线。
- `WorkPanelTests/BoardPanelControllerTests.swift` — 新建:`clampHeight` 单测。
- `WorkPanelTests/AppSettingsTests.swift` — 修改:新增 `boardHeight` 默认值/持久化单测。

> 注:`WorkPanelTests/` 下新建文件由文件系统同步组自动纳入,**不要**编辑 `project.pbxproj`。

---

## Task 1: AppSettings 新增 boardHeight

**Files:**
- Modify: `WorkPanel/Store/AppSettings.swift`
- Test: `WorkPanelTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

在 `WorkPanelTests/AppSettingsTests.swift` 的 `AppSettingsTests` struct 内,`mcpPortDefaultsTo8787` 之后追加:

```swift
    @Test func boardHeightDefaultsTo360() {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.boardHeight) }
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.boardHeight)
        #expect(AppSettings.boardHeight == 360)
    }

    @Test func boardHeightPersistsSetValue() {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.boardHeight) }
        UserDefaults.standard.set(Double(640), forKey: AppSettings.Key.boardHeight)
        #expect(AppSettings.boardHeight == 640)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AppSettingsTests 2>&1 | tail -20`
Expected: 编译失败,`Key.boardHeight` / `AppSettings.boardHeight` 未定义。

- [ ] **Step 3: Add the key and accessor**

在 `WorkPanel/Store/AppSettings.swift` 的 `Key` enum 内,`mcpToken` 之后加一行:

```swift
        static let boardHeight = "boardHeight"   // Double: 看板像素高度,360 为最小/默认
```

在 `mcpToken` 访问器之后(`}` 闭合 `enum AppSettings` 之前)加访问器:

```swift
    static var boardHeight: CGFloat {
        let h = UserDefaults.standard.double(forKey: Key.boardHeight)
        return h == 0 ? 360 : CGFloat(h)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AppSettingsTests 2>&1 | tail -20`
Expected: TEST SUCCEEDED,4 个测试(原 2 + 新 2)通过。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Store/AppSettings.swift WorkPanelTests/AppSettingsTests.swift
git commit -m "feat(board): add persisted boardHeight setting"
```

---

## Task 2: clampHeight 纯函数

**Files:**
- Modify: `WorkPanel/UI/BoardPanelController.swift`
- Test: `WorkPanelTests/BoardPanelControllerTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

新建 `WorkPanelTests/BoardPanelControllerTests.swift`:

```swift
import Testing
import AppKit
@testable import WorkPanel

@MainActor
struct BoardPanelControllerTests {
    @Test func clampReturnsValueWithinRange() {
        #expect(BoardPanelController.clampHeight(500, min: 360, max: 900) == 500)
    }

    @Test func clampFloorsAtMin() {
        #expect(BoardPanelController.clampHeight(100, min: 360, max: 900) == 360)
    }

    @Test func clampCeilingsAtMax() {
        #expect(BoardPanelController.clampHeight(1200, min: 360, max: 900) == 900)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardPanelControllerTests 2>&1 | tail -20`
Expected: 编译失败,`BoardPanelController.clampHeight` 未定义。

- [ ] **Step 3: Add the pure function**

在 `WorkPanel/UI/BoardPanelController.swift` 的 `BoardPanelController` 类内,`var isVisible` 之后加:

```swift
    /// 把高度夹紧到 [min, max]。纯函数,便于无屏幕环境单测。
    nonisolated static func clampHeight(_ proposed: CGFloat, min minH: CGFloat, max maxH: CGFloat) -> CGFloat {
        Swift.min(Swift.max(proposed, minH), maxH)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardPanelControllerTests 2>&1 | tail -20`
Expected: TEST SUCCEEDED,3 个测试通过。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/BoardPanelController.swift WorkPanelTests/BoardPanelControllerTests.swift
git commit -m "feat(board): add clampHeight pure helper"
```

---

## Task 3: BoardPanelController 高度真值源与拉伸 API

无新单测(逻辑由 Task 2 的 `clampHeight` 覆盖;frame 操作依赖真实屏幕,手动验证)。改完后整体编译通过即可。

**Files:**
- Modify: `WorkPanel/UI/BoardPanelController.swift`

- [ ] **Step 1: Replace fixed height with state + bounds**

把 `BoardPanelController` 顶部的:

```swift
    private var panel: NSPanel?
    private let height: CGFloat = 360
    private let margin: CGFloat = 16
```

替换为:

```swift
    private var panel: NSPanel?
    private let minHeight: CGFloat = 360
    private let margin: CGFloat = 16
    private var currentHeight: CGFloat = 360
    private var resizing = false
    private var dragStartHeight: CGFloat = 0

    private func maxHeight(for screen: NSScreen) -> CGFloat {
        screen.visibleFrame.height - margin * 2
    }
```

- [ ] **Step 2: Rewrite `show()` to use currentHeight**

把现有 `show(_:)` 整个方法体替换为:

```swift
    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        guard let screen = NSScreen.main else { return }
        currentHeight = Self.clampHeight(AppSettings.boardHeight,
                                         min: minHeight, max: maxHeight(for: screen))
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content())
        let visible = screen.visibleFrame
        let width = visible.width - margin * 2
        let final = NSRect(x: visible.minX + margin, y: visible.minY + margin,
                           width: width, height: currentHeight)
        let start = final.offsetBy(dx: 0, dy: -(currentHeight + margin))
        panel.setFrame(start, display: false)
        // 不调用 NSApp.activate:看板作为浮层出现,不抢占当前 App 的 active 状态。
        // nonactivatingPanel + canBecomeKey 仍能接收 Esc / ⌘, / 文本输入。
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
        }
    }
```

- [ ] **Step 3: Add resize / endResize API**

在 `toggle(_:)` 方法之后、`makePanel()` 之前,加:

```swift
    /// 拖拽把手时实时调整高度:底边锚定不动,高度向上增长。无动画。
    func resize(translationY: CGFloat) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        if !resizing { dragStartHeight = currentHeight; resizing = true }
        // 向上拖 translationY 为负 → 变高。
        currentHeight = Self.clampHeight(dragStartHeight - translationY,
                                         min: minHeight, max: maxHeight(for: screen))
        var frame = panel.frame
        frame.size.height = currentHeight
        panel.setFrame(frame, display: true)
    }

    /// 松手:落定高度并持久化。
    func endResize() {
        resizing = false
        UserDefaults.standard.set(Double(currentHeight), forKey: AppSettings.Key.boardHeight)
    }
```

- [ ] **Step 4: Use currentHeight in makePanel**

把 `makePanel()` 里:

```swift
            contentRect: NSRect(x: 0, y: 0, width: 800, height: height),
```

改为:

```swift
            contentRect: NSRect(x: 0, y: 0, width: 800, height: currentHeight),
```

- [ ] **Step 5: Verify it builds**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15`
Expected: BUILD SUCCEEDED(`BoardView` 调用点尚未传新参数 → 若此步报 `BoardView` 缺参数错误,属预期,将在 Task 4/5 修好;只要本文件无 `height` 未定义之类错误即可继续)。

> 说明:Task 3 单独不一定能通过完整 build,因为 `BoardView` 的新参数在 Task 4 才加、调用点在 Task 5 才接。可在 Task 3 仅做 `git add`+`commit`,build 验证留到 Task 5 末。

- [ ] **Step 6: Commit**

```bash
git add WorkPanel/UI/BoardPanelController.swift
git commit -m "feat(board): drive panel height from persisted state + resize API"
```

---

## Task 4: BoardView 顶部胶囊把手

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift`

- [ ] **Step 1: Add the resize closures to the struct**

把 `BoardView` 顶部的:

```swift
struct BoardView: View {
    let onClose: () -> Void
```

改为:

```swift
struct BoardView: View {
    let onClose: () -> Void
    let onResizeChanged: (CGFloat) -> Void
    let onResizeEnded: () -> Void
```

- [ ] **Step 2: Insert the handle at the top of the VStack**

把 `body` 里的:

```swift
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)
            content
        }
```

改为:

```swift
        VStack(spacing: 0) {
            resizeHandle
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)
            content
        }
```

- [ ] **Step 3: Define the handle view**

在 `private var header: some View {` 之前,加:

```swift
    private var resizeHandle: some View {
        Capsule()
            .fill(Theme.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { onResizeChanged($0.translation.height) }
                    .onEnded { _ in onResizeEnded() }
            )
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .accessibilityLabel("调整看板高度")
    }
```

- [ ] **Step 4: Commit**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat(board): add top capsule resize handle"
```

---

## Task 5: 接线并整体验证

**Files:**
- Modify: `WorkPanel/WorkPanelApp.swift`

- [ ] **Step 1: Wire the closures in toggleBoard**

把 `WorkPanelApp.swift` 的:

```swift
        board.show {
            BoardView(onClose: { [weak self] in self?.board.hide() })
                .modelContainer(SharedModel.container)
        }
```

改为:

```swift
        board.show {
            BoardView(
                onClose: { [weak self] in self?.board.hide() },
                onResizeChanged: { [weak self] dy in self?.board.resize(translationY: dy) },
                onResizeEnded: { [weak self] in self?.board.endResize() }
            )
            .modelContainer(SharedModel.container)
        }
```

- [ ] **Step 2: Build the whole app**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: Run the unit suites**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardPanelControllerTests -only-testing:WorkPanelTests/AppSettingsTests 2>&1 | tail -20`
Expected: TEST SUCCEEDED。

- [ ] **Step 4: Manual verification (人工)**

启动 App → 打开看板(快捷键)→ 拖动顶部胶囊把手:
- 向上拖,看板变高,底边不动;拖到屏幕顶附近停在最大高度。
- 向下拖,看板变矮,停在 360 不再变小。
- 悬停把手时光标为上下箭头。
- 收起看板再打开,高度沿用上次;`defaults read <bundleid> boardHeight` 能看到写入值。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/WorkPanelApp.swift
git commit -m "feat(board): wire resize handle to panel controller"
```

---

## Self-Review Notes

- **Spec coverage:** 顶部胶囊把手(Task 4)、底边锚定向上增长(Task 3 resize)、min 360 / max 屏幕可用高度(Task 2/3)、持久化与打开时夹紧(Task 1/3)、`resizeUpDown` 光标(Task 4)、`clampHeight` 单测(Task 2)、持久化读取单测(Task 1)、拖拽手动验证(Task 5)均有对应任务。
- **Type consistency:** `clampHeight(_:min:max:)`、`resize(translationY:)`、`endResize()`、`onResizeChanged`/`onResizeEnded`、`Key.boardHeight`/`AppSettings.boardHeight` 在各任务中签名一致。
- **Placeholder scan:** 无 TBD/TODO,所有改动给出完整代码。
