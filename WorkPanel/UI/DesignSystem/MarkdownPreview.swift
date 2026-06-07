import SwiftUI

/// 复选框的纯文本切换逻辑(可测,不依赖 UI)。
enum MarkdownCheckbox {
    /// 切换第 lineIndex 行的复选框:`[ ]`/`[]` ↔ `[x]`。非复选框行原样返回。
    nonisolated static func toggle(in text: String, lineIndex: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return text }
        let line = lines[lineIndex]
        if let r = line.range(of: "[x]", options: .caseInsensitive) {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "[ ]")
        } else if let r = line.range(of: "[ ]") {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "[x]")
        } else if let r = line.range(of: "[]") {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "[x]")
        }
        return lines.joined(separator: "\n")
    }
}

/// markdown 预览:按行渲染标题/列表/复选框/段落。复选框可点击切换(写回 text)。
struct MarkdownPreview: View {
    @Binding var text: String

    private enum Block {
        case heading(level: Int, text: String)
        case checkbox(checked: Bool, text: String)
        case bullet(text: String)
        case ordered(number: String, text: String)
        case paragraph(String)
        case blank
    }

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                row(classify(line), lineIndex: idx)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ block: Block, lineIndex: Int) -> some View {
        switch block {
        case .blank:
            Color.clear.frame(height: 6)
        case .heading(let level, let t):
            Text(inline(t)).font(headingFont(level)).bold()
        case .checkbox(let checked, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    text = MarkdownCheckbox.toggle(in: text, lineIndex: lineIndex)
                } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                Text(inline(t))
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
            }
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(t))
            }
        case .ordered(let n, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
                Text(inline(t))
            }
        case .paragraph(let line):
            Text(inline(line))
        }
    }

    private func classify(_ line: String) -> Block {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return .blank }
        if let m = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
            return .heading(level: m.output.1.count, text: String(m.output.2))
        }
        if let m = line.firstMatch(of: /^\s*(?:[-*+]\s+)?\[([ xX]?)\]\s+(.*)$/) {
            return .checkbox(checked: m.output.1.lowercased() == "x", text: String(m.output.2))
        }
        if let m = line.firstMatch(of: /^\s*[-*+]\s+(.*)$/) {
            return .bullet(text: String(m.output.1))
        }
        if let m = line.firstMatch(of: /^\s*(\d+)\.\s+(.*)$/) {
            return .ordered(number: String(m.output.1), text: String(m.output.2))
        }
        return .paragraph(line)
    }

    /// 行内 markdown(加粗/斜体/代码/链接);解析失败则原样。
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }
}
