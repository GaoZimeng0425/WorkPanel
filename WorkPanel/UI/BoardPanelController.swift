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
    private let height: CGFloat = 360
    private let margin: CGFloat = 16

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content())
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = visible.width - margin * 2
        let final = NSRect(x: visible.minX + margin, y: visible.minY + margin,
                           width: width, height: height)
        let start = final.offsetBy(dx: 0, dy: -(height + margin))
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

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: height),
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
