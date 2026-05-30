import SwiftUI
import AppKit

/// 单文本域 markdown 编辑器:编辑时即时套用样式(标记保留可见,方案 A)。
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSave: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CaptureTextView()
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.onCancel = onCancel
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = MarkdownStyler.baseFont
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.autoresizingMask = [.width]
        textView.string = text
        if let storage = textView.textStorage { MarkdownStyler.apply(to: storage) }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? CaptureTextView else { return }
        textView.onSave = onSave
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
            if let storage = textView.textStorage { MarkdownStyler.apply(to: storage) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownTextEditor
        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            if let storage = tv.textStorage { MarkdownStyler.apply(to: storage) }
        }
    }
}

/// 普通 Return = 换行;⌘Return = 保存;esc = 取消。
final class CaptureTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) {  // 36 = Return
            onSave?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {  // esc
        onCancel?()
    }
}

/// 用 TextKit 给 NSTextStorage 套 markdown 样式(标记保留可见)。
enum MarkdownStyler {
    static let baseFont = NSFont.systemFont(ofSize: 13)

    static func apply(to storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let ns = storage.string as NSString

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: full)

        // 行级:第一行=标题样式;# 标题;> 引用
        ns.enumerateSubstrings(in: full, options: [.byLines]) { sub, lineRange, _, _ in
            let line = sub ?? ""
            if lineRange.location == 0 {
                storage.addAttribute(.font,
                    value: NSFont.systemFont(ofSize: baseFont.pointSize + 5, weight: .semibold),
                    range: lineRange)
            }
            if let level = headingLevel(line) {
                let size = baseFont.pointSize + CGFloat(max(1, 6 - level * 2))
                storage.addAttribute(.font,
                    value: NSFont.systemFont(ofSize: size, weight: .bold), range: lineRange)
            } else if line.hasPrefix("> ") {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
            }
        }

        // 行内:加粗、斜体(用 NSFontManager 叠加 trait,可与已有样式组合)、行内代码
        addTrait(.boldFontMask, pattern: "(\\*\\*|__)(.+?)\\1", to: storage)
        addTrait(.italicFontMask, pattern: "(?<![\\*_])([\\*_])([^\\*_]+)\\1(?![\\*_])", to: storage)
        styleCode("`([^`]+)`", to: storage)

        storage.endEditing()
    }

    private static func headingLevel(_ line: String) -> Int? {
        var n = 0
        for ch in line { if ch == "#" { n += 1 } else { break } }
        guard (1...3).contains(n) else { return nil }
        return line.dropFirst(n).first == " " ? n : nil
    }

    private static func addTrait(_ trait: NSFontTraitMask, pattern: String, to storage: NSTextStorage) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(location: 0, length: storage.length)
        let fm = NSFontManager.shared
        re.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let r = match?.range else { return }
            storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                let f = (value as? NSFont) ?? baseFont
                storage.addAttribute(.font, value: fm.convert(f, toHaveTrait: trait), range: sub)
            }
        }
    }

    private static func styleCode(_ pattern: String, to storage: NSTextStorage) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(location: 0, length: storage.length)
        re.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.font,
                value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular), range: r)
            storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: r)
        }
    }
}
