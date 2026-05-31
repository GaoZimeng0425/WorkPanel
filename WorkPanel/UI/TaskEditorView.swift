import SwiftUI
import SwiftData

/// 创建 / 编辑任务的统一编辑器:单个 markdown 文本域,第一行为标题,其余为备注。
/// 第一行可用自然语言 token(如「明天 !高 #工作」)设置截止/优先级/标签/重复;
/// 编辑态缺省即保留(不通过删 token 清除)。⌘↩ 保存 / esc 取消。
struct TaskEditorView: View {
    enum Mode {
        case create(columnID: UUID?)
        case edit(TodoTask)
    }

    let mode: Mode
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    private var todoStore: TodoStore { TodoStore(context: context) }
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    @State private var text: String
    @State private var previewing = false
    @State private var priority: Priority
    @State private var selectedTags: [String]
    @State private var columnID: UUID?
    private let base: ParsedInput

    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    @Query private var allTasks: [TodoTask]

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let columnID):
            _text = State(initialValue: "")
            var b = ParsedInput()
            b.priority = AppSettings.defaultPriority
            base = b
            _priority = State(initialValue: AppSettings.defaultPriority)
            _selectedTags = State(initialValue: [])
            _columnID = State(initialValue: columnID)
        case .edit(let task):
            _text = State(initialValue: task.notes.isEmpty ? task.title : task.title + "\n" + task.notes)
            var b = ParsedInput()
            b.deadline = task.deadline
            b.priority = task.priority
            b.tags = task.tags
            b.recurrence = task.recurrence
            b.urgencyOverride = task.urgencyOverride
            base = b
            _priority = State(initialValue: task.priority)
            _selectedTags = State(initialValue: task.tags)
            _columnID = State(initialValue: task.columnID)
        }
    }

    private var allTags: [String] {
        Array(Set(allTasks.flatMap(\.tags))).sorted()
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var resolved: (fields: ParsedInput, notes: String) {
        CaptureDraft.resolve(text: text, base: base, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isEditing ? "编辑任务" : "新建任务")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                NoirSegmented(
                    segments: [.init(value: false, label: "编辑"),
                               .init(value: true, label: "预览")],
                    selection: $previewing
                )
                .fixedSize()
            }

            TokenStrip(fields: resolved.fields)

            Group {
                if previewing {
                    ScrollView { MarkdownPreview(text: $text).padding(8) }
                } else {
                    MarkdownTextEditor(text: $text, onSave: save, onCancel: onClose)
                }
            }
            .frame(height: 220)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.stroke))

            controls

            HStack {
                Text("第一行为标题 · ⌘↩ 保存 · esc 取消")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("取消") { onClose() }
                    .buttonStyle(NoirPillButtonStyle())
                Button("保存") { save() }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .disabled(resolved.fields.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlRow("重要程度") {
                NoirSegmented(
                    segments: Priority.allCases.reversed().map {
                        .init(value: $0, label: Theme.priorityLabel($0))
                    },
                    selection: $priority
                )
            }
            controlRow("状态") { statusMenu }
            controlRow("标签") {
                TagPickerField(selected: $selectedTags, existing: allTags)
            }
        }
    }

    private func controlRow<C: View>(_ label: String,
                                     @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .frame(width: 56, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var currentColumnName: String {
        guard let id = columnID else { return "无" }
        return columns.first { $0.id == id }?.name ?? "无"
    }

    private var statusMenu: some View {
        Menu {
            Button { columnID = nil } label: {
                if columnID == nil { Label("无", systemImage: "checkmark") } else { Text("无") }
            }
            ForEach(columns) { col in
                Button { columnID = col.id } label: {
                    if columnID == col.id { Label(col.name, systemImage: "checkmark") }
                    else { Text(col.name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentColumnName)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .noirPickerPill()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func save() {
        let r = resolved
        let title = r.fields.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        var fields = CaptureDraft.applyControls(to: r.fields,
                                                priority: priority,
                                                tags: selectedTags)
        fields.title = title

        let task: TodoTask
        switch mode {
        case .create:
            task = todoStore.add(fields, notes: r.notes)
        case .edit(let existing):
            existing.title = title
            existing.notes = r.notes
            existing.deadline = fields.deadline
            existing.priority = fields.priority
            existing.tags = fields.tags
            existing.recurrence = fields.recurrence
            existing.urgencyOverride = fields.urgencyOverride
            task = existing
        }
        boardStore.setColumn(task, to: columnID)
        try? context.save()
        Task { await scheduler.schedule(for: task) }
        onClose()
    }
}

/// 编辑器上方的解析预览条:实时显示从第一行解析出的优先级/截止/标签/重复。
private struct TokenStrip: View {
    let fields: ParsedInput

    var body: some View {
        let chips = chipTexts
        HStack(spacing: 6) {
            ForEach(chips, id: \.self) { c in
                Text(c)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.surface, in: Capsule())
            }
            if chips.isEmpty {
                Text("可在第一行用如「明天 18:00 每周一」补充")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var chipTexts: [String] {
        var out: [String] = []
        if let u = fields.urgencyOverride {
            out.append(u ? "紧急" : "不紧急")
        }
        if let d = fields.deadline {
            out.append(d.formatted(date: .abbreviated, time: .shortened))
        }
        if let r = fields.recurrence {
            out.append(Theme.recurrenceLabel(r))
        }
        return out
    }
}
