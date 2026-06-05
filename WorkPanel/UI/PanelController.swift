import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: NSPanel?
    /// 记忆用户拖动后的位置与尺寸,跨进程持久化(AppKit 自动存到 UserDefaults)。
    private let frameAutosaveName = "WorkPanelTaskEditorFrame"

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        let isNew = panel == nil
        let panel = panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: content())
        // 只让 hosting 暴露「最小尺寸」约束:它会按内容的 minWidth/minHeight(460×460)给窗口设下硬地板,
        // 即便无边框实时拖边也缩不进去;同时不暴露 ideal/max,故向上可自由拉伸(上限由 windowWillResize 夹)。
        hosting.sizingOptions = [.minSize]
        panel.contentView = hosting
        // 首次创建时定位:有保存过的 frame 就恢复(位置+尺寸),否则居中。
        // 之后复用同一面板,不再重置,保持用户上次摆放的位置。
        if isNew {
            if !panel.setFrameUsingName(frameAutosaveName) {
                positionCentered(panel)
            }
            panel.setFrameAutosaveName(frameAutosaveName)
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 可自由拉伸宽高(拖任意边/角),受上下限约束。
        // 无边框面板实时拖边不会自动卡 min/max,交给 KeyablePanel.windowWillResize 夹取。
        panel.minSize = NSSize(width: 460, height: 460)
        panel.maxSize = NSSize(width: 900, height: 1100)
        panel.delegate = panel
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
