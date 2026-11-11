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

    // MARK: - list_jira_tasks

    @Test func listJiraTasksReturnsOnlyJiraSourced() async throws {
        let (h, ctx, _) = try makeHandlers()
        let local = TodoTask(title: "本地"); ctx.insert(local)
        let jira = TodoTask(title: "JIRA-42 修 bug"); jira.jiraKey = "JIRA-42"
        jira.jiraSyncedAt = Date(timeIntervalSince1970: 1000)
        ctx.insert(jira); try ctx.save()

        let dtos = try decodeArray(try await h.call("list_jira_tasks", .object([:])))
        #expect(dtos.count == 1)
        #expect(dtos[0].jiraKey == "JIRA-42")
        #expect(dtos[0].jiraSyncedAt == ISO8601Date.string(Date(timeIntervalSince1970: 1000)))
    }

    @Test func listJiraTasksFiltersByCompleted() async throws {
        let (h, ctx, _) = try makeHandlers()
        let open = TodoTask(title: "开着"); open.jiraKey = "A-1"; ctx.insert(open)
        let done = TodoTask(title: "完成"); done.jiraKey = "A-2"
        done.isCompleted = true; done.completedAt = .now
        ctx.insert(done); try ctx.save()

        let all = try decodeArray(try await h.call("list_jira_tasks", .object([:])))
        let closed = try decodeArray(try await h.call("list_jira_tasks", ["completed": true]))
        #expect(all.count == 2 && closed.count == 1 && closed[0].jiraKey == "A-2")
    }

    @Test func localTaskDTOSerializesNullJiraFields() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "本地"); ctx.insert(t); try ctx.save()
        #expect(try decodeTask(try await h.call("get_task", ["id": .string(t.id.uuidString)])).jiraKey == nil)
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

    @Test func completeTaskCancelsNotificationAndReturnsTask() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "完成我", deadline: Date(timeIntervalSinceNow: 3600))
        ctx.insert(t); try ctx.save()

        let json = try await h.call("complete_task", ["id": .string(t.id.uuidString)])
        let result = try JSONDecoder().decode(CompleteResult.self, from: Data(json.utf8))
        #expect(result.task.isCompleted == true)
        #expect(result.next == nil)
        #expect(mock.removed.contains(t.id.uuidString))
    }

    @Test func completeRecurringSchedulesNext() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "每天站会", deadline: Date(timeIntervalSinceNow: 3600), recurrence: .daily)
        ctx.insert(t); try ctx.save()

        let json = try await h.call("complete_task", ["id": .string(t.id.uuidString)])
        let result = try JSONDecoder().decode(CompleteResult.self, from: Data(json.utf8))
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

    @Test func createTaskAcceptsFractionalSecondsDeadline() async throws {
        let (h, _, _) = try makeHandlers()
        let json = try await h.call("create_task", ["title": "x", "deadline": "2026-06-03T09:00:00.000Z"])
        #expect(try decodeTask(json).deadline != nil)
    }

    @Test func createTaskRejectsMalformedDeadline() async throws {
        let (h, _, _) = try makeHandlers()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("create_task", ["title": "x", "deadline": "nope"])
        }
    }

    @Test func createTaskRejectsMalformedStartDate() async throws {
        let (h, _, _) = try makeHandlers()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("create_task", ["title": "x", "startDate": "nope"])
        }
    }

    @Test func createTaskAcceptsStartDate() async throws {
        let (h, _, _) = try makeHandlers()
        let start = ISO8601Date.string(Date(timeIntervalSince1970: 1000))
        let json = try await h.call("create_task", ["title": "带开始", "startDate": .string(start)])
        #expect(try decodeTask(json).startDate == start)
    }

    @Test func updateTaskSetsAndClearsStartDate() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "改开始")
        ctx.insert(t); try ctx.save()

        let start = ISO8601Date.string(Date(timeIntervalSince1970: 2000))
        let set = try await h.call("update_task", ["id": .string(t.id.uuidString), "startDate": .string(start)])
        #expect(try decodeTask(set).startDate == start)

        let cleared = try await h.call("update_task", ["id": .string(t.id.uuidString), "startDate": .null])
        #expect(try decodeTask(cleared).startDate == nil)
    }

    // MARK: - Recurrence

    @Test func createTaskAcceptsRecurrence() async throws {
        let (h, _, _) = try makeHandlers()
        let json = try await h.call("create_task", ["title": "每天站会", "recurrence": "daily"])
        #expect(try decodeTask(json).recurrence == "daily")
    }

    @Test func createTaskRejectsBadRecurrence() async throws {
        let (h, _, _) = try makeHandlers()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("create_task", ["title": "x", "recurrence": "hourly"])
        }
    }

    @Test func updateTaskSetsAndClearsRecurrence() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "改重复"); ctx.insert(t); try ctx.save()

        let set = try await h.call("update_task", ["id": .string(t.id.uuidString), "recurrence": "weekly"])
        #expect(try decodeTask(set).recurrence == "weekly")

        let cleared = try await h.call("update_task", ["id": .string(t.id.uuidString), "recurrence": .null])
        #expect(try decodeTask(cleared).recurrence == nil)
    }

    // MARK: - Urgency override

    @Test func createTaskAcceptsUrgentOverride() async throws {
        let (h, _, _) = try makeHandlers()
        // No deadline → would be non-urgent; override forces true.
        let json = try await h.call("create_task", ["title": "盯紧", "urgent": true])
        #expect(try decodeTask(json).isUrgent == true)
    }

    @Test func updateTaskSetsAndClearsUrgentOverride() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "改紧急"); ctx.insert(t); try ctx.save()

        let set = try await h.call("update_task", ["id": .string(t.id.uuidString), "urgent": true])
        #expect(try decodeTask(set).isUrgent == true)
        #expect(t.urgencyOverride == true)

        let cleared = try await h.call("update_task", ["id": .string(t.id.uuidString), "urgent": .null])
        #expect(t.urgencyOverride == nil)   // back to auto (no deadline → not urgent)
        #expect(try decodeTask(cleared).isUrgent == false)
    }

    // MARK: - DTO exposes snooze

    @Test func dtoExposesSnoozedUntil() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "推迟我"); ctx.insert(t); try ctx.save()
        let until = ISO8601Date.string(Date(timeIntervalSince1970: 99999))

        _ = try await h.call("snooze_task", ["id": .string(t.id.uuidString), "until": .string(until)])
        let dto = try decodeTask(try await h.call("get_task", ["id": .string(t.id.uuidString)]))
        #expect(dto.snoozedUntil == until)
    }

    // MARK: - startAfter filter

    @Test func listTasksFiltersByStartAfter() async throws {
        let (h, ctx, _) = try makeHandlers()
        let early = TodoTask(title: "早"); early.startDate = Date(timeIntervalSince1970: 1000)
        let late = TodoTask(title: "晚"); late.startDate = Date(timeIntervalSince1970: 9000)
        let none = TodoTask(title: "无")
        [early, late, none].forEach { ctx.insert($0) }
        try ctx.save()

        let cutoff = ISO8601Date.string(Date(timeIntervalSince1970: 5000))
        let json = try await h.call("list_tasks", ["startAfter": .string(cutoff)])
        #expect(try decodeArray(json).map(\.title) == ["晚"])
    }
}
