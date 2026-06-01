import AppKit
import SwiftUI

/// 轻量浮层提示(仿 NemoNoise 的 ToastWindowController):用一个无激活 NSPanel 承载
/// SwiftUI 胶囊,从下方滑入、数秒后自动滑出。用于「已复制」等一次性成功反馈。
/// 面板不抢 key、忽略鼠标事件,因此设置面板在提示出现时仍可正常交互。
@MainActor
enum Notice {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ message: String, duration: TimeInterval = 1.8) {
        dismissTask?.cancel()
        removePanel()

        let hosting = NSHostingView(rootView: NoticeCapsule(message: message))
        hosting.sizingOptions = .preferredContentSize
        let fitting = hosting.fittingSize

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: fitting),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .modalPanel                 // 高于设置面板(.floating)
        p.ignoresMouseEvents = true           // 纯提示,点击穿透
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting

        // 锚定在鼠标所在屏幕,水平居中、靠近底部。
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - fitting.width / 2
        let targetY = visible.minY + 90

        let start = NSRect(x: x, y: targetY - 28, width: fitting.width, height: fitting.height)
        let end = NSRect(x: x, y: targetY, width: fitting.width, height: fitting.height)
        p.setFrame(start, display: false)
        p.alphaValue = 0
        p.orderFront(nil)                     // 不用 makeKey,避免抢走设置面板焦点
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(end, display: true)
            p.animator().alphaValue = 1
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    static func dismiss() {
        guard let p = panel else { return }
        let f = p.frame
        let out = NSRect(x: f.origin.x, y: f.origin.y - 28, width: f.width, height: f.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(out, display: true)
            p.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { removePanel() }
        })
    }

    private static func removePanel() {
        panel?.close()
        panel = nil
    }
}

private struct NoticeCapsule: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.success)
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom),
            in: Capsule()
        )
        .overlay(Capsule().stroke(Theme.strokeStrong, lineWidth: 0.7))
        .fixedSize()
        .preferredColorScheme(.dark)
    }
}
