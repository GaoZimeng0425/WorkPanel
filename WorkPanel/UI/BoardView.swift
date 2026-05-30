import SwiftUI
import SwiftData

struct BoardView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    @State private var renaming: BoardColumn?
    @State private var renameText = ""
    @State private var addingColumn = false
    @State private var newColumnText = ""

    private var store: BoardStore { BoardStore(context: context) }
    private var todoStore: TodoStore { TodoStore(context: context) }
    private let scheduler = ReminderScheduler()

    private let columnWidth: CGFloat = 220

    private var validIDs: Set<UUID> { Set(columns.map(\.id)) }

    private func columnID(for task: TodoTask) -> UUID? {
        if let id = task.columnID, validIDs.contains(id) { return id }
        return columns.first?.id          // nil 或失效 id 归第一列
    }

    private func activeTasks(in column: BoardColumn) -> [TodoTask] {
        tasks.filter { !$0.isCompleted && columnID(for: $0) == column.id }
             .sorted { $0.boardOrder < $1.boardOrder }
    }

    private var archivedTasks: [TodoTask] {
        tasks.filter { $0.isCompleted }
             .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { columnView($0) }
                    archiveColumnView
                    addColumnButton
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { store.seedDefaultColumnsIfNeeded(); try? context.save() }
        .onKeyPress(.escape) { onClose(); return .handled }
        .alert("重命名列", isPresented: Binding(get: { renaming != nil },
                                              set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") {
                if let col = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.rename(col, to: renameText); try? context.save()
                }
                renaming = nil
            }
        }
        .alert("新建列", isPresented: $addingColumn) {
            TextField("名称", text: $newColumnText)
            Button("取消", role: .cancel) { newColumnText = "" }
            Button("添加") {
                let name = newColumnText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.addColumn(name: name); try? context.save() }
                newColumnText = ""
            }
        }
    }

    private var header: some View {
        HStack {
            Text("看板").font(.headline)
            Text("\(tasks.filter { !$0.isCompleted }.count) 项").foregroundStyle(.secondary).font(.caption)
            Spacer()
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            Text("esc 收起").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 活动列

    private func columnView(_ column: BoardColumn) -> some View {
        let items = activeTasks(in: column)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name).font(.subheadline).bold()
                Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                CreateTaskButton(columnID: column.id)
                    .frame(width: 22)
                Menu {
                    Button("重命名") { renameText = column.name; renaming = column }
                    Button("删除", role: .destructive) { store.delete(column); try? context.save() }
                        .disabled(columns.count <= 1)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 22)
            }

            ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                card(task)
                    .dropDestination(for: String.self) { dropped, _ in
                        handleDrop(dropped, into: column.id, at: index); return true
                    }
            }

            addTaskField(column)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            handleDrop(dropped, into: column.id, at: items.count); return true
        }
    }

    private func addTaskField(_ column: BoardColumn) -> some View {
        AddTaskField { title in
            let parsed = InputParser().parse(title, now: .now, defaultPriority: AppSettings.defaultPriority)
            guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let task = TodoTask(title: parsed.title, deadline: parsed.deadline,
                                priority: parsed.priority, tags: parsed.tags,
                                recurrence: parsed.recurrence)
            task.columnID = column.id
            task.boardOrder = activeTasks(in: column).count
            context.insert(task)
            try? context.save()
            Task { await scheduler.schedule(for: task) }
        }
    }

    // MARK: - 归档列(虚拟)

    private var archiveColumnView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("归档").font(.subheadline).bold()
                Text("\(archivedTasks.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
            }
            ForEach(archivedTasks) { task in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(task.title).strikethrough().foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .draggable(task.id.uuidString)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            handleArchiveDrop(dropped); return true
        }
    }

    private var addColumnButton: some View {
        Button { addingColumn = true } label: {
            Image(systemName: "plus").font(.title3).frame(width: 44, height: 60)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .frame(alignment: .top)
    }

    // MARK: - 卡片

    private func card(_ task: TodoTask) -> some View {
        TaskCardView(task: task, onComplete: { complete(task) }) { EmptyView() }
            .draggable(task.id.uuidString)
            .contextMenu {
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task); context.delete(task); try? context.save()
                }
            }
            .taskEditPopover(task)
    }

    // MARK: - 拖拽处理

    private func task(for uuidString: String) -> TodoTask? {
        guard let id = UUID(uuidString: uuidString) else { return nil }
        return tasks.first { $0.id == id }
    }

    private func handleDrop(_ dropped: [String], into columnID: UUID, at index: Int) {
        guard let s = dropped.first, let task = task(for: s) else { return }
        if task.isCompleted { todoStore.reopen(task) }   // 从归档拖回
        store.move(task, to: columnID, at: index)
        try? context.save()
    }

    private func handleArchiveDrop(_ dropped: [String]) {
        guard let s = dropped.first, let task = task(for: s), !task.isCompleted else { return }
        complete(task)
    }

    private func complete(_ task: TodoTask) {
        let next = todoStore.complete(task)
        try? context.save()
        scheduler.cancel(for: task)
        if let next { Task { await scheduler.schedule(for: next) } }
    }

}

/// 列底快速新建输入框。回车提交后清空。
private struct AddTaskField: View {
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("+ 添加任务", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .onSubmit { onSubmit(text); text = "" }
    }
}
