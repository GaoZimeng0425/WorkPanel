import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content())
        positionCentered(panel)
        // 不调用 NSApp.activate:捕获面板作为浮层出现,不抢占当前 App 的 active 状态。
        // nonactivatingPanel + canBecomeKey 仍能成为 key 并接收文本输入(与 BoardPanelController 一致)。
        panel.makeKeyAndOrderFront(nil)
        // 打开即聚焦文本域,无需先点一下。MarkdownEngine 的 NSTextView 不会自动成为第一响应者,
        // 故在内容布局完成后主动指派(下一 runloop 时其 NSTextView 已建好)。
        DispatchQueue.main.async { [weak panel] in
            guard let panel, let content = panel.contentView,
                  let textView = Self.firstTextView(in: content) else { return }
            panel.makeFirstResponder(textView)
        }
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle<Content: View>(@ViewBuilder _ content: () -> Content) {
        if isVisible { hide() } else { show(content) }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
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
