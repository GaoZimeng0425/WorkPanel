// WorkPanel/MCP/MCPToolHandlers.swift
import Foundation
import SwiftData

enum ToolError: Error, CustomStringConvertible {
    case notFound(String)
    case badArgument(String)

    var description: String {
        switch self {
        case .notFound(let m): return m
        case .badArgument(let m): return m
        }
    }
}

@MainActor
final class MCPToolHandlers {
    private let context: ModelContext
    private let todo: TodoStore
    private let board: BoardStore
    private let scheduler: ReminderScheduler

    init(context: ModelContext, scheduler: ReminderScheduler = ReminderScheduler()) {
        self.context = context
        self.todo = TodoStore(context: context)
        self.board = BoardStore(context: context)
        self.scheduler = scheduler
    }

    /// Routes an MCP tool name + arguments object to its handler, returning a JSON text payload.
    func call(_ name: String, _ args: JSONValue) async throws -> String {
        switch name {
        case "list_tasks":   return try listTasks(args)
        case "get_task":     return try getTask(args)
        case "list_columns": return try listColumns()
        default: throw ToolError.badArgument("Unknown tool: \(name)")
        }
    }

    // MARK: - Read tools

    private func listTasks(_ args: JSONValue) throws -> String {
        var tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        if let completed = args["completed"]?.boolValue {
            tasks = tasks.filter { $0.isCompleted == completed }
        }
        if let s = args["columnID"]?.stringValue, let col = UUID(uuidString: s) {
            tasks = tasks.filter { $0.columnID == col }
        }
        if let tag = args["tag"]?.stringValue {
            tasks = tasks.filter { $0.tags.contains(tag) }
        }
        if let p = args["priority"]?.stringValue, let pr = Priority(apiName: p) {
            tasks = tasks.filter { $0.priority == pr }
        }
        if let s = args["dueBefore"]?.stringValue, let date = ISO8601Date.date(s) {
            tasks = tasks.filter { ($0.deadline ?? .distantFuture) < date }
        }
        return try encode(tasks.map(dto))
    }

    private func getTask(_ args: JSONValue) throws -> String {
        try encode(dto(fetchTask(requireID(args))))
    }

    private func listColumns() throws -> String {
        try encode(board.columns().map(ColumnDTO.init))
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func columnName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return board.columns().first { $0.id == id }?.name
    }

    private func dto(_ task: TodoTask) -> TaskDTO {
        TaskDTO(task, columnName: columnName(for: task.columnID))
    }

    private func requireID(_ args: JSONValue) throws -> UUID {
        guard let s = args["id"]?.stringValue, let id = UUID(uuidString: s) else {
            throw ToolError.badArgument("Missing or invalid 'id'")
        }
        return id
    }

    private func fetchTask(_ id: UUID) throws -> TodoTask {
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        guard let task = all.first(where: { $0.id == id }) else {
            throw ToolError.notFound("No task with id \(id.uuidString)")
        }
        return task
    }
}
