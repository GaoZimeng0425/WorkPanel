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
