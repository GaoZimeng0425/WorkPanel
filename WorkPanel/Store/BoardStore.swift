import Foundation
import SwiftData

@MainActor
final class BoardStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func columns() -> [BoardColumn] {
        (try? context.fetch(
            FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.order)])
        )) ?? []
    }

    var firstColumn: BoardColumn? { columns().first }

    /// 库中没有任何列时,建三列并把现有未完成任务归入第一列。否则不动。
    func seedDefaultColumnsIfNeeded() {
        guard columns().isEmpty else { return }
        let created = ["计划中", "开发中", "测试中"].enumerated().map {
            BoardColumn(name: $1, order: $0)
        }
        created.forEach { context.insert($0) }
        guard let first = created.first else { return }

        let incomplete = ((try? context.fetch(FetchDescriptor<TodoTask>())) ?? [])
            .filter { !$0.isCompleted }
            .sorted(by: TaskFilter.sortRule)
        for (i, task) in incomplete.enumerated() {
            task.columnID = first.id
            task.boardOrder = i
        }
    }

    @discardableResult
    func addColumn(name: String) -> BoardColumn {
        let nextOrder = (columns().map(\.order).max() ?? -1) + 1
        let col = BoardColumn(name: name, order: nextOrder)
        context.insert(col)
        return col
    }

    func rename(_ column: BoardColumn, to name: String) {
        column.name = name
    }

    /// 按传入数组顺序重新赋 order(0,1,2,…)。
    func reorder(_ ordered: [BoardColumn]) {
        for (i, col) in ordered.enumerated() { col.order = i }
    }

    /// 删除列;列内任务移到第一列。至少保留一个活动列(只剩一列时不删)。
    func delete(_ column: BoardColumn, now: Date = .now) {
        let cols = columns()
        guard cols.count > 1, let target = cols.first(where: { $0.id != column.id })
        else { return }
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        for task in tasks where task.columnID == column.id {
            task.columnID = target.id
        }
        let id = column.id
        context.delete(column)
        context.insert(Tombstone(id: id, kind: .column, deletedAt: now))
    }

    /// 把 task 放到目标列「第 index 个卡片之前」(insert-before),并把该列未完成任务的
    /// boardOrder 重排为 0,1,2,…。同列向下移动时,移除自身后目标索引需前移一位。
    func move(_ task: TodoTask, to columnID: UUID, at index: Int) {
        let movingWithinColumn = (task.columnID == columnID)
        let oldOrder = task.boardOrder
        task.columnID = columnID
        var siblings = ((try? context.fetch(FetchDescriptor<TodoTask>())) ?? [])
            .filter { !$0.isCompleted && $0.columnID == columnID && $0.id != task.id }
            .sorted { $0.boardOrder < $1.boardOrder }
        var target = index
        if movingWithinColumn && oldOrder < index { target -= 1 }
        target = max(0, min(target, siblings.count))
        siblings.insert(task, at: target)
        for (i, t) in siblings.enumerated() { t.boardOrder = i }
    }

    /// 设置任务状态(所属看板列)。目标为某列时追加到该列末尾并重排;目标为 nil 时清空状态。
    func setColumn(_ task: TodoTask, to columnID: UUID?) {
        guard task.columnID != columnID else { return }
        if let columnID {
            move(task, to: columnID, at: .max)   // .max 经 move 内部 clamp 到末尾
        } else {
            task.columnID = nil
        }
    }

    /// 优先级透镜拖拽落入某列时调用,仅改 priority(无序号语义)。
    func setPriority(_ task: TodoTask, to priority: Priority) {
        task.priority = priority
    }
}
