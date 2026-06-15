import SwiftUI
import SwiftData

/// 看板过滤栏:搜索 + 优先级药丸 + 紧急药丸 + 标签多选 + 清除。
/// 写入注入环境的 BoardFilter;各透镜读取并应用。
struct BoardFilterBar: View {
    @Bindable var filter: BoardFilter
    @Query(sort: \Tag.order) private var allTags: [Tag]

    @State private var showTags = false

    var body: some View {
        HStack(spacing: 10) {
            searchField
            priorityPills
            urgentPill
            tagButton
            Spacer(minLength: 0)
            if filter.isActive {
                Button("清除") { filter.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            TextField("搜索标题/备注", text: $filter.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 140)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.surfaceSubtle, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Theme.stroke, lineWidth: 0.6))
    }

    private var priorityPills: some View {
        HStack(spacing: 4) {
            ForEach([Priority.high, .medium, .low], id: \.self) { p in
                togglePill(label: Theme.priorityLabel(p),
                           tint: Theme.priority(p),
                           on: filter.priorities.contains(p)) {
                    if filter.priorities.contains(p) { filter.priorities.remove(p) }
                    else { filter.priorities.insert(p) }
                }
            }
        }
    }

    private var urgentPill: some View {
        togglePill(label: "⚡ 紧急", tint: Theme.accent, on: filter.urgentOnly) {
            filter.urgentOnly.toggle()
        }
    }

    private var tagButton: some View {
        Button { showTags = true } label: {
            HStack(spacing: 4) {
                Text(filter.tags.isEmpty ? "标签" : "标签 \(filter.tags.count)")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(filter.tags.isEmpty ? Theme.textSecondary : Theme.accentText)
            .noirPickerPill()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTags, arrowEdge: .bottom) { tagPopover }
    }

    private var tagPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if allTags.isEmpty {
                    Text("还没有标签")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                }
                ForEach(allTags) { tag in
                    Button {
                        if filter.tags.contains(tag.name) { filter.tags.remove(tag.name) }
                        else { filter.tags.insert(tag.name) }
                    } label: {
                        HStack {
                            Text("#\(tag.name)").foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if filter.tags.contains(tag.name) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .font(.system(size: 12))
                        .contentShape(Rectangle())
                        .padding(.horizontal, 9).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 260)
        .frame(width: 200)
        .background(Theme.panelBottom)
        .preferredColorScheme(.dark)
    }

    private func togglePill(label: String, tint: Color, on: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.black : tint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(on ? tint : Color.clear))
                .overlay(Capsule(style: .continuous).stroke(tint.opacity(0.7), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}
