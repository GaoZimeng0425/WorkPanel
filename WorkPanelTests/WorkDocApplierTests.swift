import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct WorkDocApplierTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, Tag.self, Tombstone.self, DayPlan.self,
            configurations: config)
        return ModelContext(container)
    }

    @Test func createInsertsTaskWithColumnAndTags() throws {
        let ctx = try makeContext()
        let col = UUID()
        let cs = WorkDocument.ChangeSet(
            creates: [.init(title: "新任务", notes: "备注", priority: .high, tags: ["工作"],
                            columnID: col, order: 0)],
            updates: [], deletes: [])
        WorkDocApplier(context: ctx).apply(cs)

        let tasks = try ctx.fetch(FetchDescriptor<TodoTask>())
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "新任务")
        #expect(tasks[0].notes == "备注")
        #expect(tasks[0].priority == .high)
        #expect(tasks[0].columnID == col)
        #expect(tasks[0].boardOrder == 0)
        let tags = try ctx.fetch(FetchDescriptor<WorkPanel.Tag>())
        #expect(tags.map(\.name).contains("工作"))
    }

    @Test func updateChangesFieldsButKeepsDeadline() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "旧标题", priority: .low)
        let deadline = Date(timeIntervalSince1970: 1_900_000_000)
        task.deadline = deadline
        ctx.insert(task)
        let cs = WorkDocument.ChangeSet(creates: [],
            updates: [.init(id: task.id, title: "新标题", notes: "n", priority: .high, tags: [],
                            columnID: nil, order: 3, complete: false)],
            deletes: [])
        WorkDocApplier(context: ctx).apply(cs)

        #expect(task.title == "新标题")
        #expect(task.priority == .high)
        #expect(task.boardOrder == 3)
        #expect(task.deadline == deadline)             // 时间字段不动
        #expect(task.isCompleted == false)
    }

    @Test func completeMarksDone() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "买菜")
        ctx.insert(task)
        let cs = WorkDocument.ChangeSet(creates: [],
            updates: [.init(id: task.id, title: "买菜", notes: "", priority: .medium, tags: [],
                            columnID: nil, order: 0, complete: true)],
            deletes: [])
        WorkDocApplier(context: ctx).apply(cs)
        #expect(task.isCompleted == true)
        #expect(task.completedAt != nil)
    }

    @Test func deleteRemovesTask() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "删我")
        ctx.insert(task)
        let id = task.id
        let cs = WorkDocument.ChangeSet(creates: [], updates: [], deletes: [id])
        WorkDocApplier(context: ctx).apply(cs)

        #expect((try ctx.fetch(FetchDescriptor<TodoTask>())).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Tombstone>()).isEmpty)
    }
}
