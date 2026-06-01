// WorkPanelTests/MCPToolHandlersTests.swift
import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import WorkPanel

@MainActor
struct MCPToolHandlersTests {
    final class MockCenter: NotificationScheduling, @unchecked Sendable {
        var added: [UNNotificationRequest] = []
        var removed: [String] = []
        func add(_ request: UNNotificationRequest) async throws { added.append(request) }
        func removePendingNotificationRequests(withIdentifiers ids: [String]) { removed.append(contentsOf: ids) }
    }

    private func makeHandlers() throws -> (MCPToolHandlers, ModelContext, MockCenter) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        let context = ModelContext(container)
        let mock = MockCenter()
        let handlers = MCPToolHandlers(context: context, scheduler: ReminderScheduler(center: mock))
        return (handlers, context, mock)
    }

    private func decodeArray(_ json: String) throws -> [TaskDTO] {
        try JSONDecoder().decode([TaskDTO].self, from: Data(json.utf8))
    }
    private func decodeTask(_ json: String) throws -> TaskDTO {
        try JSONDecoder().decode(TaskDTO.self, from: Data(json.utf8))
    }

    @Test func listTasksFiltersByCompleted() async throws {
        let (h, ctx, _) = try makeHandlers()
        let a = TodoTask(title: "未完成")
        let b = TodoTask(title: "已完成"); b.isCompleted = true
        [a, b].forEach { ctx.insert($0) }
        try ctx.save()

        let open = try await h.call("list_tasks", ["completed": false])
        #expect(try decodeArray(open).map(\.title) == ["未完成"])

        let done = try await h.call("list_tasks", ["completed": true])
        #expect(try decodeArray(done).map(\.title) == ["已完成"])
    }

    @Test func getTaskReturnsOneAndThrowsWhenMissing() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "找我")
        ctx.insert(t); try ctx.save()

        let dto = try await h.call("get_task", ["id": .string(t.id.uuidString)])
        #expect(try decodeTask(dto).title == "找我")

        await #expect(throws: ToolError.self) {
            _ = try await h.call("get_task", ["id": .string(UUID().uuidString)])
        }
    }

    @Test func listColumnsReturnsColumns() async throws {
        let (h, ctx, _) = try makeHandlers()
        ctx.insert(BoardColumn(name: "计划中", order: 0))
        ctx.insert(BoardColumn(name: "开发中", order: 1))
        try ctx.save()

        let json = try await h.call("list_columns", .object([:]))
        let cols = try JSONDecoder().decode([ColumnDTO].self, from: Data(json.utf8))
        #expect(cols.map(\.name) == ["计划中", "开发中"])
    }

    @Test func createTaskInsertsAndSchedulesNotification() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let due = ISO8601Date.string(Date(timeIntervalSinceNow: 3600))
        let json = try await h.call("create_task", [
            "title": "写文档", "notes": "细节", "priority": "high",
            "tags": ["work"], "deadline": .string(due),
        ])
        let dto = try decodeTask(json)
        #expect(dto.title == "写文档")
        #expect(dto.priority == "high")
        #expect(dto.tags == ["work"])

        let stored = (try ctx.fetch(FetchDescriptor<TodoTask>()))
        #expect(stored.count == 1)
        #expect(mock.added.count == 1)   // future deadline → notification scheduled
        #expect(mock.added.first?.identifier == dto.id)
    }

    @Test func createTaskRequiresTitle() async throws {
        let (h, _, _) = try makeHandlers()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("create_task", ["notes": "无标题"])
        }
    }

    @Test func updateTaskPatchesOnlyProvidedFieldsAndReschedules() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "旧标题", notes: "旧备注",
                         deadline: Date(timeIntervalSinceNow: 3600), priority: .low)
        ctx.insert(t); try ctx.save()

        let json = try await h.call("update_task", [
            "id": .string(t.id.uuidString), "title": "新标题", "priority": "high",
        ])
        let dto = try decodeTask(json)
        #expect(dto.title == "新标题")
        #expect(dto.priority == "high")
        #expect(dto.notes == "旧备注")   // untouched (absent key)
        #expect(mock.removed.contains(t.id.uuidString))   // cancel
        #expect(mock.added.count == 1)                    // reschedule
    }

    @Test func updateTaskClearsDeadlineWhenExplicitNull() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "有截止", deadline: Date(timeIntervalSinceNow: 3600))
        ctx.insert(t); try ctx.save()

        let json = try await h.call("update_task", ["id": .string(t.id.uuidString), "deadline": .null])
        #expect(try decodeTask(json).deadline == nil)
        #expect(t.deadline == nil)
    }

    @Test func createTaskRejectsUnknownColumnID() async throws {
        let (h, _, _) = try makeHandlers()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("create_task", ["title": "x", "columnID": .string(UUID().uuidString)])
        }
    }

    @Test func updateTaskThrowsWhenMissing() async throws {
        let (h, _, _) = try makeHandlers()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("update_task", ["id": .string(UUID().uuidString), "title": "新"])
        }
    }

    struct CompleteResultDTO: Codable { let task: TaskDTO; let next: TaskDTO? }

    @Test func completeTaskCancelsNotificationAndReturnsTask() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "完成我", deadline: Date(timeIntervalSinceNow: 3600))
        ctx.insert(t); try ctx.save()

        let json = try await h.call("complete_task", ["id": .string(t.id.uuidString)])
        let result = try JSONDecoder().decode(CompleteResultDTO.self, from: Data(json.utf8))
        #expect(result.task.isCompleted == true)
        #expect(result.next == nil)
        #expect(mock.removed.contains(t.id.uuidString))
    }

    @Test func completeRecurringSchedulesNext() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "每天站会", deadline: Date(timeIntervalSinceNow: 3600), recurrence: .daily)
        ctx.insert(t); try ctx.save()

        let json = try await h.call("complete_task", ["id": .string(t.id.uuidString)])
        let result = try JSONDecoder().decode(CompleteResultDTO.self, from: Data(json.utf8))
        #expect(result.next != nil)
        #expect(mock.added.contains { $0.identifier == result.next?.id })
    }

    @Test func reopenClearsCompletion() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "恢复我"); t.isCompleted = true; t.completedAt = .now
        ctx.insert(t); try ctx.save()

        let dto = try decodeTask(try await h.call("reopen_task", ["id": .string(t.id.uuidString)]))
        #expect(dto.isCompleted == false)
    }

    @Test func snoozeSetsSnoozeWithoutTouchingNotifications() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "推迟我")
        ctx.insert(t); try ctx.save()
        let until = ISO8601Date.string(Date(timeIntervalSinceNow: 86400))

        _ = try await h.call("snooze_task", ["id": .string(t.id.uuidString), "until": .string(until)])
        #expect(t.snoozedUntil != nil)
        #expect(mock.added.isEmpty && mock.removed.isEmpty)   // snooze never touches notifications
    }

    @Test func deleteRemovesTaskAndNotification() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "删除我")
        ctx.insert(t); try ctx.save()

        let json = try await h.call("delete_task", ["id": .string(t.id.uuidString)])
        #expect(json.contains(t.id.uuidString))
        #expect((try ctx.fetch(FetchDescriptor<TodoTask>())).isEmpty)
        #expect(mock.removed.contains(t.id.uuidString))
    }

    @Test func moveTaskSetsColumnAndOrder() async throws {
        let (h, ctx, _) = try makeHandlers()
        let c0 = BoardColumn(name: "A", order: 0)
        let c1 = BoardColumn(name: "B", order: 1)
        [c0, c1].forEach { ctx.insert($0) }
        let t = TodoTask(title: "移动我"); t.columnID = c0.id
        ctx.insert(t); try ctx.save()

        let dto = try decodeTask(try await h.call("move_task", [
            "id": .string(t.id.uuidString), "columnID": .string(c1.id.uuidString), "index": 0,
        ]))
        #expect(dto.columnID == c1.id.uuidString)
        #expect(dto.columnName == "B")
    }

    @Test func moveTaskClearsColumnWhenNull() async throws {
        let (h, ctx, _) = try makeHandlers()
        let c0 = BoardColumn(name: "A", order: 0); ctx.insert(c0)
        let t = TodoTask(title: "清状态"); t.columnID = c0.id
        ctx.insert(t); try ctx.save()

        let dto = try decodeTask(try await h.call("move_task", [
            "id": .string(t.id.uuidString), "columnID": .null,
        ]))
        #expect(dto.columnID == nil)
    }

    @Test func moveTaskRejectsUnknownColumnID() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "x"); ctx.insert(t); try ctx.save()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("move_task", ["id": .string(t.id.uuidString), "columnID": .string(UUID().uuidString)])
        }
    }
}
