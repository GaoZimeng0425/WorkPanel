import Testing
import SwiftData
@testable import WorkPanel

@MainActor
struct TodoTaskTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, configurations: config)
        return ModelContext(container)
    }

    @Test func defaultsAreSane() {
        let task = TodoTask(title: "写周报")
        #expect(task.title == "写周报")
        #expect(task.notes == "")
        #expect(task.priority == .medium)
        #expect(task.deadline == nil)
        #expect(task.tags.isEmpty)
        #expect(task.isCompleted == false)
        #expect(task.recurrence == nil)
    }

    @Test func priorityAndRecurrenceRoundTripThroughStorage() throws {
        let context = try makeContext()
        let task = TodoTask(title: "回邮件", priority: .high,
                            tags: ["客户A"], recurrence: .weekly)
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TodoTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.priority == .high)
        #expect(fetched.first?.recurrence == .weekly)
        #expect(fetched.first?.tags == ["客户A"])
    }
}
