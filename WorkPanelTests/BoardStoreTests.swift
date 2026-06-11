import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct BoardStoreTests {
    private func makeStore() throws -> BoardStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, Tombstone.self, configurations: config)
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

    @Test func moveSetsColumnAndRenumbersBoardOrder() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()
        let a = TodoTask(title: "A"); a.columnID = cols[0].id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = cols[1].id; b.boardOrder = 0
        [a, b].forEach { store.context.insert($0) }

        store.move(a, to: cols[1].id, at: 0)
        #expect(a.columnID == cols[1].id)
        #expect(a.boardOrder == 0)
        #expect(b.boardOrder == 1)
    }

    @Test func moveWithinColumnReorders() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        let a = TodoTask(title: "A"); a.columnID = col.id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = col.id; b.boardOrder = 1
        let c = TodoTask(title: "C"); c.columnID = col.id; c.boardOrder = 2
        [a, b, c].forEach { store.context.insert($0) }

        store.move(c, to: col.id, at: 0)
        #expect([c.boardOrder, a.boardOrder, b.boardOrder] == ([0, 1, 2] as [Int]))
    }

    @Test func moveWithinColumnDownwardInsertsBeforeTarget() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        let a = TodoTask(title: "A"); a.columnID = col.id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = col.id; b.boardOrder = 1
        let c = TodoTask(title: "C"); c.columnID = col.id; c.boardOrder = 2
        [a, b, c].forEach { store.context.insert($0) }

        store.move(a, to: col.id, at: 2)   // 把 A 拖到 C 的位置(向下)
        // 期望 insert-before C: [B, A, C]
        #expect([b.boardOrder, a.boardOrder, c.boardOrder] == ([0, 1, 2] as [Int]))
    }

    @Test func setColumnAppendsToEndOfTargetColumnAndRenumbers() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let cols = store.columns()
        let a = TodoTask(title: "A"); a.columnID = cols[1].id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = cols[1].id; b.boardOrder = 1
        let mover = TodoTask(title: "M"); mover.columnID = cols[0].id; mover.boardOrder = 0
        [a, b, mover].forEach { store.context.insert($0) }

        store.setColumn(mover, to: cols[1].id)

        #expect(mover.columnID == cols[1].id)
        #expect([a.boardOrder, b.boardOrder, mover.boardOrder] == ([0, 1, 2] as [Int]))
    }

    @Test func setColumnToNilClearsStatus() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        let t = TodoTask(title: "T"); t.columnID = col.id; t.boardOrder = 3
        store.context.insert(t)

        store.setColumn(t, to: nil)

        #expect(t.columnID == nil)
        #expect(t.boardOrder == 3)
    }

    @Test func setColumnToSameColumnIsNoOp() throws {
        let store = try makeStore()
        store.seedDefaultColumnsIfNeeded()
        let col = store.columns().first!
        let a = TodoTask(title: "A"); a.columnID = col.id; a.boardOrder = 0
        let b = TodoTask(title: "B"); b.columnID = col.id; b.boardOrder = 1
        [a, b].forEach { store.context.insert($0) }

        store.setColumn(b, to: col.id)

        #expect([a.boardOrder, b.boardOrder] == ([0, 1] as [Int]))
    }

    @Test func setPriorityChangesPriority() throws {
        let store = try makeStore()
        let t = TodoTask(title: "T", priority: .low)
        store.context.insert(t)
        store.setPriority(t, to: .high)
        #expect(t.priority == .high)
    }

    @Test func deleteCreatesColumnTombstone() throws {
        let store = try makeStore()
        let a = store.addColumn(name: "A")
        _ = store.addColumn(name: "B")
        try store.context.save()
        store.delete(a, now: Date(timeIntervalSince1970: 100))
        try store.context.save()
        let tombs = try store.context.fetch(FetchDescriptor<Tombstone>())
        #expect(tombs.count == 1)
        #expect(tombs.first?.id == a.id)
        #expect(tombs.first?.kind == .column)
        #expect(tombs.first?.deletedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func deleteLastColumnCreatesNoTombstone() throws {
        let store = try makeStore()
        let only = store.addColumn(name: "唯一")
        try store.context.save()
        store.delete(only)
        try store.context.save()
        #expect(try store.context.fetch(FetchDescriptor<BoardColumn>()).count == 1)
        #expect(try store.context.fetch(FetchDescriptor<Tombstone>()).isEmpty)
    }
}
