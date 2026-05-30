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
}
