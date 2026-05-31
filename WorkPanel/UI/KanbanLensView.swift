import SwiftUI
import SwiftData

/// 看板透镜:用户自定义列 + 虚拟「归档」列,支持列间拖拽。
/// 内容迁自原 BoardView,行为不变。
struct KanbanLensView: View {
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
        return columns.first?.id
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { columnView($0) }
                archiveColumnView
                addColumnButton
            }
            .padding(12)
        }
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

    private func columnView(_ column: BoardColumn) -> some View {
        let items = activeTasks(in: column)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name).font(.subheadline).bold()
                Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .openTaskEditor,
                                                    object: TaskEditorView.Mode.create(columnID: column.id))
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .frame(width: 22)
                Menu {
                    Button("重命名") { renameText = column.name; renaming = column }
                    Button("删除", role: .destructive) { store.delete(column); try? context.save() }
                        .disabled(columns.count <= 1)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 22)
            }

            ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                LensCard(task: task, draggable: true)
                    .dropDestination(for: String.self) { dropped, _ in
                        handleDrop(dropped, into: column.id, at: index); return true
                    }
            }

            Button {
                NotificationCenter.default.post(name: .openTaskEditor,
                                                object: TaskEditorView.Mode.create(columnID: column.id))
            } label: {
                Text("+ 添加任务")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            handleDrop(dropped, into: column.id, at: items.count); return true
        }
    }

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
                    Text(task.title).strikethrough().foregroundStyle(.secondary).lineLimit(1)
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

    private func task(for uuidString: String) -> TodoTask? {
        guard let id = UUID(uuidString: uuidString) else { return nil }
        return tasks.first { $0.id == id }
    }

    private func handleDrop(_ dropped: [String], into columnID: UUID, at index: Int) {
        guard let s = dropped.first, let task = task(for: s) else { return }
        if task.isCompleted { todoStore.reopen(task) }
        store.move(task, to: columnID, at: index)
        try? context.save()
    }

    private func handleArchiveDrop(_ dropped: [String]) {
        guard let s = dropped.first, let task = task(for: s), !task.isCompleted else { return }
        let next = todoStore.complete(task)
        try? context.save()
        scheduler.cancel(for: task)
        if let next { Task { await scheduler.schedule(for: next) } }
    }
}
