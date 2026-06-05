import SwiftUI
import SwiftData

/// 各透镜共用的任务卡片:点按打开编辑器、勾选完成、右键删除。
/// `draggable` 默认关闭;看板与优先级透镜显式开启。
struct LensCard: View {
    let task: TodoTask
    var draggable: Bool = false

    @Environment(\.modelContext) private var context
    private var todoStore: TodoStore { TodoStore(context: context) }
    private let scheduler = ReminderScheduler()

    var body: some View {
        let card = TaskCardView(task: task, onComplete: complete) { EmptyView() }
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .openTaskEditor,
                                                object: TaskEditorView.Mode.edit(task))
            }
            .contextMenu {
                Button("删除", role: .destructive) {
                    scheduler.cancel(for: task)
                    context.delete(task)
                    try? context.saveTracking()
                }
            }
            .accessibilityIdentifier("card-\(task.title)")

        if draggable {
            card.draggable(task.id.uuidString)
        } else {
            card
        }
    }

    private func complete() {
        let next = todoStore.complete(task)
        try? context.saveTracking()
        scheduler.cancel(for: task)
        if let next { Task { await scheduler.schedule(for: next) } }
    }
}
