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
}
