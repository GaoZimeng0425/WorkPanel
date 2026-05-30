import AppKit
import SwiftUI

/// 无边框面板默认无法成为 key window;子类放开以便接收 Esc / 文本输入。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
        NSApp.activate(ignoringOtherApps: true)
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
        return panel
    }
}
