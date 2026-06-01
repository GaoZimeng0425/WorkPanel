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
    @State private var actionColumnID: UUID?

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
                Text(column.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .openTaskEditor,
                                                    object: TaskEditorView.Mode.create(columnID: column.id))
                } label: { Image(systemName: "plus") }
                .buttonStyle(NoirIconButtonStyle())
                .frame(width: 22)
                Button { actionColumnID = column.id } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.textTertiary)
                        .noirPickerPill()
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(get: { actionColumnID == column.id },
                                              set: { if !$0 { actionColumnID = nil } }),
                         arrowEdge: .bottom) {
                    columnActionsPopover(for: column)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if items.isEmpty {
                        emptyColumnText("拖入任务或点下方添加")
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                            LensCard(task: task, draggable: true)
                                .deferredDrop { handleDrop($0, into: column.id, at: index) }
                        }
                    }

                    Button {
                        NotificationCenter.default.post(name: .openTaskEditor,
                                                        object: TaskEditorView.Mode.create(columnID: column.id))
                    } label: {
                        Text("+ 添加任务")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollEdgeFade()
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .noirColumn()
        .deferredDrop { handleDrop($0, into: column.id, at: items.count) }
    }

    private var archiveColumnView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("归档")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(archivedTasks.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if archivedTasks.isEmpty {
                        emptyColumnText("完成的任务会在这里")
                    } else {
                        ForEach(archivedTasks) { task in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                Text(task.title).strikethrough()
                                    .foregroundStyle(Theme.textMuted).lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .noirCard()
                            .draggable(task.id.uuidString)
                        }
                    }
                }
            }
            .scrollEdgeFade()
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .noirColumn()
        .deferredDrop { handleArchiveDrop($0) }
    }

    private var addColumnButton: some View {
        Button { addingColumn = true } label: {
            Image(systemName: "plus").font(.title3)
                .frame(width: 44, height: 60)
        }
        .buttonStyle(NoirIconButtonStyle(size: 44))
        .noirColumn()
        .frame(alignment: .top)
    }

    private func columnActionsPopover(for column: BoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            columnActionRow("重命名", systemImage: "pencil") {
                renameText = column.name
                renaming = column
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
                .padding(.vertical, 4)
            columnActionRow("删除", systemImage: "trash", destructive: true, disabled: columns.count <= 1) {
                store.delete(column)
                try? context.save()
            }
        }
        .padding(8)
        .frame(width: 150)
        .background(Theme.panelBottom)
        .preferredColorScheme(.dark)
    }

    private func columnActionRow(_ title: String,
                                 systemImage: String,
                                 destructive: Bool = false,
                                 disabled: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        Button {
            guard !disabled else { return }
            actionColumnID = nil
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(disabled ? Theme.textMuted : (destructive ? Theme.priority(.high) : Theme.textSecondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func emptyColumnText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
    }

    private func task(for uuidString: String) -> TodoTask? {
        guard let id = UUID(uuidString: uuidString) else { return nil }
        return tasks.first { $0.id == id }
    }

    private func handleDrop(_ payload: String, into columnID: UUID, at index: Int) {
        guard let task = task(for: payload) else { return }
        if task.isCompleted { todoStore.reopen(task) }   // 从归档拖回
        store.move(task, to: columnID, at: index)
        try? context.save()
    }

    private func handleArchiveDrop(_ payload: String) {
        guard let task = task(for: payload), !task.isCompleted else { return }
        let next = todoStore.complete(task)
        try? context.save()
        scheduler.cancel(for: task)
        if let next { Task { await scheduler.schedule(for: next) } }
    }
}
