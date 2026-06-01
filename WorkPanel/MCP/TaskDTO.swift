// WorkPanel/MCP/TaskDTO.swift
import Foundation

enum ISO8601Date {
    private nonisolated(unsafe) static let plain = ISO8601DateFormatter()
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated static func string(_ date: Date) -> String { plain.string(from: date) }
    nonisolated static func date(_ s: String) -> Date? { plain.date(from: s) ?? fractional.date(from: s) }
}

extension Priority {
    nonisolated var apiName: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
    nonisolated init?(apiName: String) {
        switch apiName {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        default: return nil
        }
    }
}

struct TaskDTO: Codable, Equatable {
    let id: String
    let title: String
    let notes: String
    let deadline: String?
    let priority: String
    let tags: [String]
    let isCompleted: Bool
    let completedAt: String?
    let columnID: String?
    let columnName: String?
    let boardOrder: Int
    let isUrgent: Bool

    init(_ task: TodoTask, columnName: String?, now: Date = .now) {
        id = task.id.uuidString
        title = task.title
        notes = task.notes
        deadline = task.deadline.map(ISO8601Date.string)
        priority = task.priority.apiName
        tags = task.tags
        isCompleted = task.isCompleted
        completedAt = task.completedAt.map(ISO8601Date.string)
        columnID = task.columnID?.uuidString
        self.columnName = columnName
        boardOrder = task.boardOrder
        isUrgent = task.isUrgent(asOf: now)
    }
}

struct ColumnDTO: Codable, Equatable {
    let id: String
    let name: String
    let order: Int

    init(_ column: BoardColumn) {
        id = column.id.uuidString
        name = column.name
        order = column.order
    }
}
