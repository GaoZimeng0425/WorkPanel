import AppKit
import SwiftUI

/// 无边框面板默认无法成为 key window;子类放开以便接收 Esc / 文本输入。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Esc 收起。由各 Controller 注入具体动作(动画 / 隐藏)。
    /// 借面板层的 cancelOperation: 而非 SwiftUI .onKeyPress(.escape) —— 后者在无焦点元素的
    /// 面板(如看板)里不触发。
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// ⌘, 打开设置:命令组合键走 performKeyEquivalent: 路径,仅当本面板为 key window 时生效(非全局)。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "," {
            NotificationCenter.default.post(name: .openSettings, object: nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// 看板顶部的拉伸把手(纯交互,视觉胶囊由 SwiftUI 绘制)。
/// 用 AppKit 鼠标跟踪循环而非 SwiftUI DragGesture:mouseDown 后直接拉取 mouseDragged/mouseUp,
/// 同步缩放面板,绕开 SwiftUI 更新周期带来的抖动,且 mouseUp 一定触发 → 高度持久化可靠。
final class ResizeHandleView: NSView {
    var onBegin: (() -> Void)?
    var onDrag: (() -> Void)?
    var onEnd: (() -> Void)?

    // 浮层面板非激活,允许首次点击即开始拖拽。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        onBegin?()
        var dragging = true
        while dragging,
              let e = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                      until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if e.type == .leftMouseUp { dragging = false } else { onDrag?() }
        }
        onEnd?()
    }
}

@MainActor
final class BoardPanelController: NSObject {
    private var panel: NSPanel?
    private let minHeight: CGFloat = 360
    private let margin: CGFloat = 16
    private let handleStripHeight: CGFloat = 16   // 与 SwiftUI 胶囊条等高(胶囊 4 + 上下 padding 6)
    private var currentHeight: CGFloat = 360
    private var dragStartHeight: CGFloat = 0
    private var dragStartMouseY: CGFloat = 0

    private func maxHeight(for screen: NSScreen) -> CGFloat {
        screen.visibleFrame.height - margin * 2
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 把高度夹紧到 [min, max]。纯函数,便于无屏幕环境单测。
    nonisolated static func clampHeight(_ proposed: CGFloat, min minH: CGFloat, max maxH: CGFloat) -> CGFloat {
        Swift.min(Swift.max(proposed, minH), maxH)
    }

    /// 由拖拽起点的高度与屏幕光标 y(向上为正)算出新高度,夹紧到 [min, max]。
    /// 用屏幕绝对坐标而非视图内位移:面板向上增长会移动把手所在的视图坐标系,
    /// 若以视图内位移驱动会形成反馈回路(半速跟手 + 抖动)。屏幕坐标不随面板缩放移动。
    nonisolated static func resizedHeight(startHeight: CGFloat, startMouseY: CGFloat,
                                          currentMouseY: CGFloat, min minH: CGFloat, max maxH: CGFloat) -> CGFloat {
        clampHeight(startHeight + (currentMouseY - startMouseY), min: minH, max: maxH)
    }

    /// 上滑/下滑动画时长:与滑动距离(高度 + margin)成正比,使各高度下的滑动速度恒定。
    /// 最小高度时等于 base,避免高看板因固定时长而“一闪而过”。
    nonisolated static func slideDuration(forHeight height: CGFloat, minHeight: CGFloat,
                                          margin: CGFloat, base: CGFloat) -> CGFloat {
        base * (height + margin) / (minHeight + margin)
    }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        guard let screen = NSScreen.main else { return }
        currentHeight = Self.clampHeight(AppSettings.boardHeight,
                                         min: minHeight, max: maxHeight(for: screen))
        let panel = panel ?? makePanel()
        self.panel = panel
        let visible = screen.visibleFrame
        let width = visible.width - margin * 2
        let final = NSRect(x: visible.minX + margin, y: visible.minY + margin,
                           width: width, height: currentHeight)
        panel.contentView = makeContent(content(), size: final.size)
        let start = final.offsetBy(dx: 0, dy: -(currentHeight + margin))
        panel.setFrame(start, display: false)
        // 不调用 NSApp.activate:看板作为浮层出现,不抢占当前 App 的 active 状态。
        // nonactivatingPanel + canBecomeKey 仍能接收 Esc / ⌘, / 文本输入。
        panel.makeKeyAndOrderFront(nil)
        // 首次 orderFront 与位移动画在同一 runloop 周期时,窗口尚未在 start 完成首帧显示,
        // animator 无法插值会直接跳到 final(展开看不到动画)。推迟一帧再做上滑。
        let duration = Self.slideDuration(forHeight: currentHeight, minHeight: minHeight,
                                          margin: margin, base: 0.28)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(final, display: true)
                }
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        let target = panel.frame.offsetBy(dx: 0, dy: -(panel.frame.height + margin))
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.slideDuration(forHeight: panel.frame.height, minHeight: minHeight,
                                              margin: margin, base: 0.22)
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { panel.orderOut(nil) })
    }

    func toggle<Content: View>(@ViewBuilder _ content: () -> Content) {
        if isVisible { hide() } else { show(content) }
    }

    /// 容器:SwiftUI 内容铺满,顶部叠一条透明的 AppKit 拉伸把手。
    private func makeContent<Content: View>(_ root: Content, size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        let hosting = NSHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let handle = ResizeHandleView(frame: NSRect(x: 0, y: size.height - handleStripHeight,
                                                    width: size.width, height: handleStripHeight))
        handle.autoresizingMask = [.width, .minYMargin]   // 贴顶、随宽度伸缩
        handle.onBegin = { [weak self] in self?.resizeBegan() }
        handle.onDrag = { [weak self] in self?.resize() }
        handle.onEnd = { [weak self] in self?.resizeEnded() }
        container.addSubview(handle)

        return container
    }

    /// 拖拽开始:记录起点高度与屏幕光标 y。
    func resizeBegan() {
        dragStartHeight = currentHeight
        dragStartMouseY = NSEvent.mouseLocation.y
    }

    /// 拖拽中:底边锚定不动,高度向上增长。以屏幕光标绝对位置驱动,与面板缩放解耦。无动画。
    func resize() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        currentHeight = Self.resizedHeight(startHeight: dragStartHeight, startMouseY: dragStartMouseY,
                                           currentMouseY: NSEvent.mouseLocation.y,
                                           min: minHeight, max: maxHeight(for: screen))
        var frame = panel.frame
        frame.size.height = currentHeight
        panel.setFrame(frame, display: true)
    }

    /// 松手:落定高度并持久化(mouseUp 必触发,持久化可靠)。
    func resizeEnded() {
        UserDefaults.standard.set(Double(currentHeight), forKey: AppSettings.Key.boardHeight)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: currentHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false          // 失焦不自动消失
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.hide() }
        return panel
    }
}
