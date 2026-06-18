import Foundation
import SwiftData

/// 把 WorkDocument.ChangeSet 落到 ModelContext。直接赋 columnID/boardOrder(文档顺序),
/// 复用 TodoStore(add/complete/delete)、TagStore(标签注册)、ReminderScheduler(后继提醒)。
@MainActor
final class WorkDocApplier {
    private let context: ModelContext
    private let todoStore: TodoStore
    private let tagStore: TagStore
    private let scheduler = ReminderScheduler()

    init(context: ModelContext) {
        self.context = context
        self.todoStore = TodoStore(context: context)
        self.tagStore = TagStore(context: context)
    }

    func apply(_ changes: WorkDocument.ChangeSet) {
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        // 新建
        for spec in changes.creates {
            var fields = ParsedInput()
            fields.title = spec.title
            fields.priority = spec.priority
            fields.tags = spec.tags
            let task = todoStore.add(fields, notes: spec.notes)
            task.columnID = spec.columnID
            task.boardOrder = spec.order
        }

        // 更新
        for spec in changes.updates {
            guard let task = byID[spec.id] else { continue }
            task.title = spec.title
            task.notes = spec.notes
            task.priority = spec.priority
            task.tags = spec.tags
            task.columnID = spec.columnID
            task.boardOrder = spec.order
            if spec.complete && !task.isCompleted {
                scheduler.cancel(for: task)
                if let follow = todoStore.complete(task) {
                    Task { await self.scheduler.schedule(for: follow) }
                }
            }
        }

        // 删除
        for id in changes.deletes {
            guard let task = byID[id] else { continue }
            scheduler.cancel(for: task)
            todoStore.delete(task)
        }

        // 标签注册
        let names = changes.creates.flatMap(\.tags) + changes.updates.flatMap(\.tags)
        tagStore.register(names: names)

        try? context.saveTracking()
    }
}
