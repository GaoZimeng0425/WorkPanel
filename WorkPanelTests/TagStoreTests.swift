import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct TagStoreTests {
    private func makeStore() throws -> TagStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, Tag.self, configurations: config)
        return TagStore(context: ModelContext(container))
    }

    @Test func registerInsertsTrimmedAndDedupes() throws {
        let store = try makeStore()
        store.register("  工作 ")
        store.register("工作")
        store.register("")
        store.register("   ")
        #expect(store.all().map(\.name) == ["工作"])
        #expect(store.all().first?.order == 0)
    }

    @Test func registerAppendsIncreasingOrder() throws {
        let store = try makeStore()
        store.register("a")
        store.register("b")
        store.register("c")
        #expect(store.all().map(\.order) == [0, 1, 2])
    }

    @Test func deleteRemovesTagRowAndSweepsTasks() throws {
        let store = try makeStore()
        let t1 = TodoTask(title: "一", tags: ["工作", "家"])
        let t2 = TodoTask(title: "二", tags: ["工作"])
        [t1, t2].forEach { store.context.insert($0) }
        store.register("工作"); store.register("家")

        store.delete("工作")

        #expect(store.all().map(\.name) == ["家"])
        #expect(t1.tags == ["家"])
        #expect(t2.tags == [])
    }

    @Test func seedFromTasksGeneratesFromTaskTagsWhenEmpty() throws {
        let store = try makeStore()
        let t1 = TodoTask(title: "一", tags: ["b", "a"])
        let t2 = TodoTask(title: "二", tags: ["a", "c"])
        [t1, t2].forEach { store.context.insert($0) }

        store.seedFromTasksIfNeeded()

        #expect(store.all().map(\.name) == ["a", "b", "c"])
    }

    @Test func seedDoesNothingWhenTagsExist() throws {
        let store = try makeStore()
        store.register("已有")
        let t = TodoTask(title: "一", tags: ["新"]); store.context.insert(t)

        store.seedFromTasksIfNeeded()

        #expect(store.all().map(\.name) == ["已有"])
    }

    @Test func reconcileAddsMissingNamesKeepsExisting() throws {
        let store = try makeStore()
        store.register("旧")
        let t = TodoTask(title: "一", tags: ["旧", "导入来的"]); store.context.insert(t)

        store.reconcileFromTasks()

        #expect(store.all().map(\.name) == ["旧", "导入来的"])
        #expect(store.all().first?.order == 0)
    }
}
