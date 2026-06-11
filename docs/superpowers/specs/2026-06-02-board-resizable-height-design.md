# 看板可拉伸高度 — 设计文档

日期: 2026-06-02

## 目标

看板浮层当前固定高度 `360`。让用户可以把看板向上拉高,在一个**最小高度**与**最大高度**之间自由拉伸;拉伸后的高度在重启 App 后记住。

## 现状

- 看板是无边框 `NSPanel`(`KeyablePanel`),锚定在屏幕底部:`y = visibleFrame.minY + margin`,宽度铺满减去左右 `margin`。
- `BoardPanelController` 持有固定 `let height: CGFloat = 360`,`show()` 时从底部滑入、`hide()` 时滑出。
- 面板内容是 `BoardView`(SwiftUI),通过 `NSHostingView` 填充面板。
- 偏好统一存在 `AppSettings`(`UserDefaults` 封装)。

## 设计

### 交互

- 在 `BoardView` 顶部边缘放一个**可见的胶囊把手**(居中的小横条指示器),作为拉伸的视觉提示。
- 把手上向上拖 = 看板变高,向下拖 = 看板变矮。
- 底边始终锚定不动,高度向上增长。
- 悬停把手时光标变为 `NSCursor.resizeUpDown`。

### 高度范围

- 最小 / 默认高度:`360`(沿用当前值)。
- 最大高度:`screen.visibleFrame.height - margin * 2`(屏幕可用高度减去上下边距)。
- 拉伸后的高度通过 `UserDefaults` 记住,下次打开看板沿用;若持久化值超出当前屏幕范围(如换了显示器),在 `show()` 时夹紧到 `[min, max]`。

### 数据流

```
拖拽把手 (SwiftUI DragGesture)
   → onResizeChanged(translationY) / onResizeEnded()  闭包
   → BoardPanelController 实时 setFrame(无动画, origin.y 不变, height 变化)
   → 松手时 controller 把 currentHeight 写入 AppSettings
```

`BoardPanelController` 是高度的唯一真值来源(single source of truth)。

## 组件改动

### 1. `AppSettings` (WorkPanel/Store/AppSettings.swift)

- `Key` 新增 `boardHeight = "boardHeight"`(Double)。
- 新增类型化访问器 `boardHeight: CGFloat`:读 `UserDefaults`,未设置时返回 `360`。
  - 不在 `registerDefaults` 注册具体值;访问器在缺省/为 0 时回落到 `360`(与 `mcpPort` 的写法一致)。
- 写入由 controller 在拖拽结束时调用 `UserDefaults.standard.set(_, forKey: Key.boardHeight)`。

### 2. `BoardPanelController` (WorkPanel/UI/BoardPanelController.swift)

替换固定 `height`:

- `private let minHeight: CGFloat = 360`
- `private func maxHeight(for screen: NSScreen) -> CGFloat { screen.visibleFrame.height - margin * 2 }`
- `private var currentHeight: CGFloat`,在 `show()` 中从 `AppSettings.boardHeight` 读取并夹紧到 `[minHeight, maxHeight(for:)]`。
- `show()` / `makePanel()` 中所有用到 `height` 的地方改用 `currentHeight`;滑入起始偏移用 `currentHeight + margin`。

拉伸 API(由把手拖拽驱动):

- 拖拽开始(首个 onChanged):记录 `dragStartHeight = currentHeight`。
- `func resize(translationY: CGFloat)`:`proposed = dragStartHeight - translationY`(向上拖 translationY 为负 → 变高),夹紧到 `[minHeight, maxHeight]`,赋给 `currentHeight`,`setFrame`(**无动画**,`origin.y` 不变,只改 `height`)。
- `func endResize()`:把 `currentHeight` 写入 `AppSettings`,清拖拽进行中标记。
- 用一个 `private var resizing = false` 标记区分拖拽起始,以在首个 `resize(translationY:)` 时锁定 `dragStartHeight`。

夹紧逻辑抽成可测的纯函数:

```swift
nonisolated static func clampHeight(_ proposed: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat
```

(`nonisolated` 以符合本项目 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` 的约定,便于在无屏幕环境下单测。)

### 3. `BoardView` (WorkPanel/UI/BoardView.swift)

- 新增两个闭包参数:`let onResizeChanged: (CGFloat) -> Void`、`let onResizeEnded: () -> Void`。
- 在 `body` 的 `VStack` 顶部、`header` 之上,插入把手视图:
  - 居中的胶囊指示器(`Capsule().fill(...)`,约 36×4pt),外层加足够的垂直点击区(约 12–16pt 高)以便抓取。
  - `.gesture(DragGesture().onChanged { onResizeChanged($0.translation.height) }.onEnded { _ in onResizeEnded() })`。
  - `.onHover` 时 push/pop `NSCursor.resizeUpDown`。
- 视觉沿用现有 `Theme`(描边/前景色),与磨砂卡片风格一致。

### 4. `WorkPanelApp.toggleBoard()` (WorkPanel/WorkPanelApp.swift)

构造 `BoardView` 时接上新闭包:

```swift
BoardView(
    onClose: { [weak self] in self?.board.hide() },
    onResizeChanged: { [weak self] dy in self?.board.resize(translationY: dy) },
    onResizeEnded: { [weak self] in self?.board.endResize() }
)
```

## 边界情况

- 持久化高度 > 当前屏幕可用高度(换显示器/分辨率变化):`show()` 时夹紧到 `maxHeight`。
- 持久化高度 < `minHeight` 或未设置:回落到 `360`。
- 拖拽过程中实时无动画 setFrame,避免与 0.28s 滑入动画打架(滑入/收起动画保持不变)。

## 测试

- 单测 `clampHeight(_:min:max:)`:
  - 超过 max → 返回 max。
  - 低于 min → 返回 min。
  - 区间内 → 原值返回。
- 单测持久化读取:`AppSettings.boardHeight` 未设置时返回 `360`;设置越界值后经 `clampHeight` 夹紧。
- 拖拽手势本身依据记忆 [[xcuitest-cannot-drive-swiftui-draggable]] 不在 XCUITest 中可靠驱动,手动验证即可。

## 不做(YAGNI)

- 不做横向拉伸(宽度保持铺满)。
- 不做四边拉伸,只支持顶边向上。
- 不加最小/最大高度的用户可配置项,固定为 360 / 屏幕可用高度。
