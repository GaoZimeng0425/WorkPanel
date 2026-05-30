import AppKit
import SwiftUI

extension Notification.Name {
    /// 任一入口(菜单栏齿轮 / 看板齿轮 / 面板内 ⌘,)请求打开设置面板。
    static let openSettings = Notification.Name("openSettings")
    /// object 携带 `TaskEditorView.Mode`：请求在捕获面板中打开任务编辑器。
    static let openTaskEditor = Notification.Name("openTaskEditor")
}

/// 居中浮窗设置面板。仿 PanelController,但**失焦不自动关闭**(手动关闭:完成按钮 / Esc)。
@MainActor
final class SettingsPanelController {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: content())
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)   // 面板尺寸跟随 SwiftUI 内容,避免裁切/留白
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
        panel.onCancel = { [weak self] in self?.hide() }
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
