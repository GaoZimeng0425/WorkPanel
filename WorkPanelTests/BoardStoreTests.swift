import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct BoardStoreTests {
    private func makeStore() throws -> BoardStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, configurations: config)
        return BoardStore(context: ModelContext(container))
    }

    @Test func seedCreatesThreeColumnsWhenEmpty() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        try store.context.save()
        let cols = store.columns()
        #expect(cols.map(\.name) == ["计划中", "开发中", "测试中"])
        #expect(cols.map(\.order) == [0, 1, 2])
    }

    @Test func seedAssignsIncompleteTasksToFirstColumnInSortOrder() throws {
        let store = try makeStore()
        let low = TodoTask(title: "低", priority: .low)
        let high = TodoTask(title: "高", priority: .high)
        let done = TodoTask(title: "完成了"); done.isCompleted = true
        [low, high, done].forEach { store.context.insert($0) }

        store.seedDefaultColumnsIfNeeded()
        try store.context.save()

        let first = store.columns().first!
        #expect(high.columnID == first.id)
        #expect(low.columnID == first.id)
        #expect(done.columnID == nil)
        #expect(high.boardOrder == 0)
        #expect(low.boardOrder == 1)
    }

    @Test func seedDoesNothingWhenColumnsExist() throws {
        let store = try makeStore()
        store.context.insert(BoardColumn(name: "已有", order: 0))
        store.seedDefaultColumnsIfNeeded()
        #expect(store.columns().map(\.name) == ["已有"])
    }

    @Test func addColumnAppendsWithNextOrder() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.addColumn(name: "上线")
        #expect(col.order == 3)
        #expect(store.columns().map(\.name) == ["计划中", "开发中", "测试中", "上线"])
    }

    @Test func renameChangesName() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        store.rename(col, to: "待办")
        #expect(store.columns().first!.name == "待办")
    }

    @Test func reorderAssignsSequentialOrder() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()
        store.reorder([cols[2], cols[0], cols[1]])
        #expect(store.columns().map(\.name) == ["测试中", "计划中", "开发中"])
    }

    @Test func deleteReassignsTasksToFirstColumn() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()
        let task = TodoTask(title: "在第二列")
        task.columnID = cols[1].id
        store.context.insert(task)

        store.delete(cols[1])
        #expect(store.columns().count == 2)
        #expect(task.columnID == cols[0].id)
    }

    @Test func deleteIsNoOpWhenOnlyOneColumn() throws {
        let store = try makeStore()
        let only = store.addColumn(name: "唯一")
        store.delete(only)
        #expect(store.columns().count == 1)
    }
}
