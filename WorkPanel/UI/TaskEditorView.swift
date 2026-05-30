import SwiftUI
import SwiftData

/// 创建 / 编辑任务的统一编辑器。在捕获面板(PanelController)中居中呈现。
/// 本地 @State 草稿,显式 ⌘↩ 保存 / esc 取消;创建与编辑由 Mode 决定 seeding 与保存动作。
struct TaskEditorView: View {
    enum Mode {
        case create(columnID: UUID?)
        case edit(TodoTask)
    }

    let mode: Mode
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    private var todoStore: TodoStore { TodoStore(context: context) }
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    @State private var title: String
    @State private var notes: String
    @State private var deadline: Date?
    @State private var priority: Priority
    @State private var tags: [String]
    @State private var recurrence: RecurrenceRule?
    @State private var columnID: UUID?

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let columnID):
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _deadline = State(initialValue: nil)
            _priority = State(initialValue: AppSettings.defaultPriority)
            _tags = State(initialValue: [])
            _recurrence = State(initialValue: nil)
            _columnID = State(initialValue: columnID)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _notes = State(initialValue: task.notes)
            _deadline = State(initialValue: task.deadline)
            _priority = State(initialValue: task.priority)
            _tags = State(initialValue: task.tags)
            _recurrence = State(initialValue: task.recurrence)
            _columnID = State(initialValue: task.columnID)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "编辑任务" : "新建任务").font(.headline)

            TaskFormFields(
                title: $title, notes: $notes, deadline: $deadline,
                priority: $priority, tags: $tags, recurrence: $recurrence,
                columnID: $columnID, columns: columns)

            HStack {
                Spacer()
                Button("取消") { onClose() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { save(); return .handled }
            return .ignored
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let task: TodoTask
        switch mode {
        case .create:
            var parsed = ParsedInput()
            parsed.title = trimmed
            parsed.deadline = deadline
            parsed.priority = priority
            parsed.tags = tags
            parsed.recurrence = recurrence
            task = todoStore.add(parsed, notes: notes)
        case .edit(let existing):
            existing.title = trimmed
            existing.notes = notes
            existing.deadline = deadline
            existing.priority = priority
            existing.tags = tags
            existing.recurrence = recurrence
            task = existing
        }
        boardStore.setColumn(task, to: columnID)
        try? context.save()
        Task { await scheduler.schedule(for: task) }
        onClose()
    }
}
