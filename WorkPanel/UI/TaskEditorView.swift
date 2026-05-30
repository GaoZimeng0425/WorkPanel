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
    private let base: ParsedInput
    private let columnID: UUID?

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let columnID):
            _text = State(initialValue: "")
            var b = ParsedInput()
            b.priority = AppSettings.defaultPriority
            base = b
            self.columnID = columnID
        case .edit(let task):
            _text = State(initialValue: task.notes.isEmpty ? task.title : task.title + "\n" + task.notes)
            var b = ParsedInput()
            b.deadline = task.deadline
            b.priority = task.priority
            b.tags = task.tags
            b.recurrence = task.recurrence
            base = b
            self.columnID = task.columnID
        }
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
            Text(isEditing ? "编辑任务" : "新建任务").font(.headline)

            TokenStrip(fields: resolved.fields)

            MarkdownTextEditor(text: $text, onSave: save, onCancel: onClose)
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Text("第一行为标题 · ⌘↩ 保存 · esc 取消")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { onClose() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(resolved.fields.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
    }

    private func save() {
        let r = resolved
        let title = r.fields.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        var fields = r.fields
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
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if chips.count <= 1 {
                Text("可在第一行用如「明天 !高 #工作」补充")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var chipTexts: [String] {
        var out: [String] = [Theme.priorityLabel(fields.priority)]
        if let d = fields.deadline {
            out.append(d.formatted(date: .abbreviated, time: .shortened))
        }
        out += fields.tags.map { "#\($0)" }
        if let r = fields.recurrence {
            out.append(Theme.recurrenceLabel(r))
        }
        return out
    }
}
