import SwiftUI
import SwiftData

/// 创建 / 编辑任务的统一弹窗内容。两种模式共用 `TaskFormFields`。
struct TaskEditorView: View {
    enum Mode {
        case edit(TodoTask)
        case create(columnID: UUID?)
    }
    let mode: Mode

    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    var body: some View {
        Group {
            switch mode {
            case .edit(let task):
                EditEditor(task: task, columns: columns)
            case .create(let columnID):
                CreateEditor(initialColumnID: columnID, columns: columns)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// 编辑已存在任务:字段绑定到模型,改即生效;关闭时持久化并重排提醒。
private struct EditEditor: View {
    @Bindable var task: TodoTask
    let columns: [BoardColumn]

    @Environment(\.modelContext) private var context
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    var body: some View {
        TaskFormFields(
            title: $task.title,
            notes: $task.notes,
            deadline: $task.deadline,
            priority: $task.priority,
            tags: $task.tags,
            recurrence: $task.recurrence,
            columnID: Binding(get: { task.columnID },
                              set: { boardStore.setColumn(task, to: $0); try? context.save() }),
            columns: columns)
        .onDisappear {
            try? context.save()
            Task { await scheduler.schedule(for: task) }
        }
    }
}

/// 新建任务:本地草稿,保存按钮 / ⌘↩ 才落库。
private struct CreateEditor: View {
    let columns: [BoardColumn]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private var todoStore: TodoStore { TodoStore(context: context) }
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    @State private var title = ""
    @State private var notes = ""
    @State private var deadline: Date? = nil
    @State private var priority: Priority
    @State private var tags: [String] = []
    @State private var recurrence: RecurrenceRule? = nil
    @State private var columnID: UUID?

    init(initialColumnID: UUID?, columns: [BoardColumn]) {
        self.columns = columns
        _priority = State(initialValue: AppSettings.defaultPriority)
        _columnID = State(initialValue: initialColumnID)
    }

    var body: some View {
        VStack(spacing: 12) {
            TaskFormFields(
                title: $title, notes: $notes, deadline: $deadline,
                priority: $priority, tags: $tags, recurrence: $recurrence,
                columnID: $columnID, columns: columns)

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { save(); return .handled }
            return .ignored
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var parsed = ParsedInput()
        parsed.title = trimmed
        parsed.deadline = deadline
        parsed.priority = priority
        parsed.tags = tags
        parsed.recurrence = recurrence
        let task = todoStore.add(parsed, notes: notes)
        boardStore.setColumn(task, to: columnID)
        try? context.save()
        Task { await scheduler.schedule(for: task) }
        dismiss()
    }
}

/// 点击触发编辑 popover 的修饰符。每次应用持有独立的展示状态。
struct TaskEditPopover: ViewModifier {
    let task: TodoTask
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { show = true }
            .popover(isPresented: $show, arrowEdge: .trailing) {
                TaskEditorView(mode: .edit(task))
            }
    }
}

extension View {
    func taskEditPopover(_ task: TodoTask) -> some View {
        modifier(TaskEditPopover(task: task))
    }
}

/// 新建任务按钮:点击弹出创建 popover。columnID 预选状态(nil = 无状态)。
struct CreateTaskButton: View {
    let columnID: UUID?
    @State private var show = false

    var body: some View {
        Button { show = true } label: { Image(systemName: "plus.circle") }
            .buttonStyle(.borderless)
            .popover(isPresented: $show, arrowEdge: .bottom) {
                TaskEditorView(mode: .create(columnID: columnID))
            }
    }
}
