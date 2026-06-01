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
}
