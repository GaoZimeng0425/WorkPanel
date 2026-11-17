import SwiftUI
import SwiftData

/// 看板透镜:用户自定义列 + 虚拟「归档」列,支持列间拖拽。
/// 内容迁自原 BoardView,行为不变。
struct KanbanLensView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    @Environment(BoardFilter.self) private var filter

    @State private var renaming: BoardColumn?
    @State private var renameText = ""
    @State private var addingColumn = false
    @State private var newColumnText = ""
    @State private var actionColumnID: UUID?

    private var store: BoardStore { BoardStore(context: context) }
    private var todoStore: TodoStore { TodoStore(context: context) }
    private let scheduler = ReminderScheduler()

    private let columnWidth: CGFloat = 260

    private var validIDs: Set<UUID> { Set(columns.map(\.id)) }

    private func columnID(for task: TodoTask) -> UUID? {
        if let id = task.columnID, validIDs.contains(id) { return id }
        return columns.first?.id
    }

    private func activeTasks(in column: BoardColumn) -> [TodoTask] {
        column.sort.sorted(
            filter.apply(tasks).filter { !$0.isCompleted && columnID(for: $0) == column.id },
            descending: column.sortDescending)
    }

    private var archivedTasks: [TodoTask] {
        filter.apply(tasks).filter { $0.isCompleted }
             .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        GeometryReader { geo in
            // 等宽列:可用宽度均分给 c+1 个弹性列(含归档);列多到放不下时退回最小宽横向滚动。
            let flexCount = CGFloat(columns.count + 1)
            let chrome = 24.0 + 12.0 * flexCount + 150.0   // 外 padding + 列间距 + 「加列」按钮
            let width = max(columnWidth, (geo.size.width - chrome) / flexCount)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { columnView($0, width: width) }
                    archiveColumnView(width: width)
                    addColumnButton
                }
                .padding(12)
            }
        }
        .alert("重命名列", isPresented: Binding(get: { renaming != nil },
                                              set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") {
                if let col = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.rename(col, to: renameText); try? context.saveTracking()
                }
                renaming = nil
            }
        }
        .alert("新建列", isPresented: $addingColumn) {
            TextField("名称", text: $newColumnText)
            Button("取消", role: .cancel) { newColumnText = "" }
            Button("添加") {
                let name = newColumnText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.addColumn(name: name); try? context.saveTracking() }
                newColumnText = ""
            }
        }
    }

    private func columnView(_ column: BoardColumn, width: CGFloat) -> some View {
        let items = activeTasks(in: column)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)   // chip 挤占时列名优雅收缩截断
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                if column.sort != .manual {
                    SortChip(column: column) {
                        store.toggleSortDirection(column)
                        try? context.saveTracking()
                    } onClear: {
                        store.clearSort(column)
                        try? context.saveTracking()
                    }
                }
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
                        ForEach(items) { task in
                            LensCard(task: task, draggable: true)
                                .reorderRow(id: task.id, in: column.id)
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
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .noirColumn()
        .reorderContainer(space: column.id, order: items.map(\.id)) { payload, index in
            handleDrop(payload, into: column.id, at: index)
        }
    }

    private func archiveColumnView(width: CGFloat) -> some View {
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
        .frame(width: width)
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
            // 排序小节:当前生效项打勾,点击切换并落库;手动不进菜单——清除唯一入口是列头 chip 的 ×
            Text("排序")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 9)
            ForEach(ColumnSortOption.allCases.filter { $0 != .manual }) { option in
                Button {
                    store.setSort(column, to: option)
                    try? context.saveTracking()
                    actionColumnID = nil
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if column.sort == option {
                            Image(systemName: "checkmark")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
                .padding(.vertical, 4)
            // 方向小节:当前方向打勾;手动排序无方向,整节置灰
            Text("方向")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 9)
            sortDirectionRow("升序", systemImage: "arrow.up",
                             isCurrent: !column.sortDescending,
                             disabled: column.sort == .manual) {
                column.sortDescending = false
                try? context.saveTracking()
            }
            sortDirectionRow("降序", systemImage: "arrow.down",
                             isCurrent: column.sortDescending,
                             disabled: column.sort == .manual) {
                column.sortDescending = true
                try? context.saveTracking()
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
                .padding(.vertical, 4)
            columnActionRow("重命名", systemImage: "pencil") {
                renameText = column.name
                renaming = column
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
                .padding(.vertical, 4)
            columnActionRow("删除", systemImage: "trash", destructive: true, disabled: columns.count <= 1) {
                store.delete(column)
                try? context.saveTracking()
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

    /// 方向小节行:直接写 column.sortDescending + 落库(不走 setSort——它会重置到该依据的常用方向)。
    private func sortDirectionRow(_ title: String,
                                  systemImage: String,
                                  isCurrent: Bool,
                                  disabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button {
            guard !disabled else { return }
            actionColumnID = nil
            action()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isCurrent && !disabled {
                    Image(systemName: "checkmark")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(disabled ? Theme.textMuted : Theme.textSecondary)
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
        try? context.saveTracking()
    }

    private func handleArchiveDrop(_ payload: String) {
        guard let task = task(for: payload), !task.isCompleted else { return }
        Task { await todoStore.completeAndReschedule(task, scheduler: scheduler) }
    }
}

/// 列头排序 chip(排序生效时列头唯一排序控件,手动态不渲染):
/// 点本体 = 翻转方向,点 × = 清除排序回手动。视觉 = 小号 noirBadge 变体:
/// accentText 前景 + accentSoft 底的胶囊,10pt rounded bold,hover 提亮。
private struct SortChip: View {
    let column: BoardColumn
    let onToggle: () -> Void
    let onClear: () -> Void

    @State private var hovering = false
    @State private var hoveringBody = false
    @State private var hoveringX = false

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onToggle) {
                HStack(spacing: 3) {
                    Text(column.sort.label).lineLimit(1)
                    Image(systemName: column.sortDescending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                // 原型 .sc-toggle:hover 的 #ffb37a 提亮(Theme 无对应 token)
                .foregroundStyle(hoveringBody ? Color(red: 1, green: 0.70, blue: 0.48) : Theme.accentText)
                .padding(.horizontal, 2).padding(.vertical, 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringBody = $0 }
            .help("排序:\(column.sort.label) · \(column.sortDescending ? "降序" : "升序") · 点此处切换方向,点 × 清除")

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hoveringX ? Theme.textPrimary : Theme.accentText.opacity(0.68))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(hoveringX ? Color.white.opacity(0.14) : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringX = $0 }
            .help("清除排序(回到手动)")
        }
        .padding(.leading, 8).padding(.trailing, 5).padding(.vertical, 2)
        .fixedSize()
        .background(Capsule(style: .continuous)
            .fill(hovering ? Theme.accent.opacity(0.26) : Theme.accentSoft))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
