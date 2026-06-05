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

struct CompleteResult: Codable {
    let task: TaskDTO
    let next: TaskDTO?
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
        case "create_task":  return try await createTask(args)
        case "update_task":  return try await updateTask(args)
        case "complete_task": return try await completeTask(args)
        case "reopen_task":   return try reopenTask(args)
        case "snooze_task":   return try snoozeTask(args)
        case "delete_task":   return try deleteTask(args)
        case "move_task":     return try moveTask(args)
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
        if args.contains("dueBefore") {
            guard let s = args["dueBefore"]?.stringValue, let date = ISO8601Date.date(s) else {
                throw ToolError.badArgument("Invalid 'dueBefore'")
            }
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

    // MARK: - Create / update

    private func createTask(_ args: JSONValue) async throws -> String {
        guard let title = args["title"]?.stringValue, !title.isEmpty else {
            throw ToolError.badArgument("Missing 'title'")
        }
        var parsed = ParsedInput()
        parsed.title = title
        parsed.priority = args["priority"]?.stringValue.flatMap(Priority.init(apiName:)) ?? .medium
        parsed.tags = args["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if args.contains("deadline"), args["deadline"]?.isNull != true {
            guard let s = args["deadline"]?.stringValue, let date = ISO8601Date.date(s) else {
                throw ToolError.badArgument("Invalid 'deadline'")
            }
            parsed.deadline = date
        }
        // validate columnID (if provided) before mutating anything
        var targetColumn: UUID? = nil
        if let s = args["columnID"]?.stringValue {
            guard let col = UUID(uuidString: s),
                  board.columns().contains(where: { $0.id == col }) else {
                throw ToolError.badArgument("Unknown columnID")
            }
            targetColumn = col
        }
        let notes = args["notes"]?.stringValue ?? ""
        let task = todo.add(parsed, notes: notes)
        if let targetColumn { board.setColumn(task, to: targetColumn) }
        try context.saveTracking()
        await scheduler.schedule(for: task)
        return try encode(dto(task))
    }

    private func updateTask(_ args: JSONValue) async throws -> String {
        let task = try fetchTask(requireID(args))
        if let v = args["title"]?.stringValue { task.title = v }
        if let v = args["notes"]?.stringValue { task.notes = v }
        if args.contains("deadline") {
            if args["deadline"]?.isNull == true { task.deadline = nil }
            else if let s = args["deadline"]?.stringValue, let d = ISO8601Date.date(s) { task.deadline = d }
            else { throw ToolError.badArgument("Invalid 'deadline'") }
        }
        if let v = args["priority"]?.stringValue, let p = Priority(apiName: v) { task.priority = p }
        if let arr = args["tags"]?.arrayValue { task.tags = arr.compactMap(\.stringValue) }
        try context.saveTracking()
        scheduler.cancel(for: task)
        await scheduler.schedule(for: task)
        return try encode(dto(task))
    }

    // MARK: - State transitions

    private func completeTask(_ args: JSONValue) async throws -> String {
        let task = try fetchTask(requireID(args))
        let next = todo.complete(task)
        try context.saveTracking()
        scheduler.cancel(for: task)
        if let next { await scheduler.schedule(for: next) }
        return try encode(CompleteResult(task: dto(task), next: next.map(dto)))
    }

    private func reopenTask(_ args: JSONValue) throws -> String {
        let task = try fetchTask(requireID(args))
        todo.reopen(task)
        try context.saveTracking()
        return try encode(dto(task))
    }

    private func snoozeTask(_ args: JSONValue) throws -> String {
        guard let s = args["until"]?.stringValue, let date = ISO8601Date.date(s) else {
            throw ToolError.badArgument("Missing or invalid 'until'")
        }
        let task = try fetchTask(requireID(args))
        todo.snooze(task, until: date)
        try context.saveTracking()
        return try encode(dto(task))
    }

    private func deleteTask(_ args: JSONValue) throws -> String {
        let id = try requireID(args)
        let task = try fetchTask(id)
        scheduler.cancel(for: task)
        todo.delete(task)
        try context.saveTracking()
        return try encode(["deleted": id.uuidString])
    }

    private func moveTask(_ args: JSONValue) throws -> String {
        let task = try fetchTask(requireID(args))
        if args.contains("columnID"), args["columnID"]?.isNull == true {
            board.setColumn(task, to: nil)
        } else if let s = args["columnID"]?.stringValue, let col = UUID(uuidString: s) {
            guard board.columns().contains(where: { $0.id == col }) else {
                throw ToolError.badArgument("Unknown columnID")
            }
            if let index = args["index"]?.intValue {
                board.move(task, to: col, at: index)
            } else {
                board.setColumn(task, to: col)
            }
        } else {
            throw ToolError.badArgument("Missing 'columnID'")
        }
        try context.saveTracking()
        return try encode(dto(task))
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
