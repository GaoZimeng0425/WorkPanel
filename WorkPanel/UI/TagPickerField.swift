import SwiftUI

/// 捕获面板的标签多选控件(GitHub Labels / Notion 多选属性 风格):
/// 收起态 pill 显示摘要;点开 popover,顶部输入框同时筛选已有标签与新建。
struct TagPickerField: View {
    @Binding var selected: [String]
    let existing: [String]          // 已有标签全集(去重排序)

    @State private var showing = false
    @State private var filter = ""

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 4) {
                Text(Self.summary(selected))
                    .foregroundStyle(selected.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Theme.surfaceEmphasis))
            .overlay(Capsule(style: .continuous).stroke(Theme.stroke, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) { popover }
    }

    private var trimmed: String { filter.trimmingCharacters(in: .whitespaces) }
    private var matches: [String] {
        guard !trimmed.isEmpty else { return existing }
        return existing.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
    private var canCreate: Bool { !trimmed.isEmpty && !existing.contains(trimmed) }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("筛选或新建标签", text: $filter)
                .textFieldStyle(.plain)
                .padding(8)
                .onSubmit { if canCreate { create() } }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if canCreate {
                        row(title: "新建『\(trimmed)』", checked: false) { create() }
                    }
                    ForEach(matches, id: \.self) { tag in
                        row(title: "#\(tag)", checked: selected.contains(tag)) { toggle(tag) }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 220)
        .background(Theme.panelBottom)
        .preferredColorScheme(.dark)
    }

    private func row(title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer()
                if checked { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ tag: String) {
        if let i = selected.firstIndex(of: tag) { selected.remove(at: i) }
        else { selected.append(tag) }
    }
    private func create() {
        guard !trimmed.isEmpty, !selected.contains(trimmed) else { return }
        selected.append(trimmed)
        filter = ""
    }

    /// 收起态摘要:0→占位「标签」;1–3→空格连名;>3→「首个 等N个标签」。
    static func summary(_ tags: [String]) -> String {
        switch tags.count {
        case 0: return "标签"
        case 1...3: return tags.joined(separator: " ")
        default: return "\(tags[0]) 等\(tags.count)个标签"
        }
    }
}
