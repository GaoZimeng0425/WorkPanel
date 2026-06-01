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

@MainActor
final class BoardPanelController: NSObject {
    private var panel: NSPanel?
    private let minHeight: CGFloat = 360
    private let margin: CGFloat = 16
    private var currentHeight: CGFloat = 360
    private var resizing = false
    private var dragStartHeight: CGFloat = 0

    private func maxHeight(for screen: NSScreen) -> CGFloat {
        screen.visibleFrame.height - margin * 2
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 把高度夹紧到 [min, max]。纯函数,便于无屏幕环境单测。
    nonisolated static func clampHeight(_ proposed: CGFloat, min minH: CGFloat, max maxH: CGFloat) -> CGFloat {
        Swift.min(Swift.max(proposed, minH), maxH)
    }

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

    func hide() {
        guard let panel, panel.isVisible else { return }
        let target = panel.frame.offsetBy(dx: 0, dy: -(panel.frame.height + margin))
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { panel.orderOut(nil) })
    }

    func toggle<Content: View>(@ViewBuilder _ content: () -> Content) {
        if isVisible { hide() } else { show(content) }
    }

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
