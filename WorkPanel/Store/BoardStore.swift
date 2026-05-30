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
    func delete(_ column: BoardColumn) {
        let cols = columns()
        guard cols.count > 1, let target = cols.first(where: { $0.id != column.id })
        else { return }
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        for task in tasks where task.columnID == column.id {
            task.columnID = target.id
        }
        context.delete(column)
    }

    /// 把 task 放到目标列的第 index 位,并把该列未完成任务的 boardOrder 重排为 0,1,2,…
    func move(_ task: TodoTask, to columnID: UUID, at index: Int) {
        task.columnID = columnID
        var siblings = ((try? context.fetch(FetchDescriptor<TodoTask>())) ?? [])
            .filter { !$0.isCompleted && $0.columnID == columnID && $0.id != task.id }
            .sorted { $0.boardOrder < $1.boardOrder }
        let clamped = max(0, min(index, siblings.count))
        siblings.insert(task, at: clamped)
        for (i, t) in siblings.enumerated() { t.boardOrder = i }
    }
}
