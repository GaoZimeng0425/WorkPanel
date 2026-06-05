import Foundation
import SwiftData

@Model
final class TodoTask {
    var id: UUID
    var title: String
    var notes: String
    var deadline: Date?
    var priorityRaw: Int
    var tags: [String]
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var snoozedUntil: Date?
    var recurrenceRaw: String?
    var columnID: UUID?
    var boardOrder: Int
    var planOrder: Int = 0           // 开工规划页手动排序;仅 PlanningView 候选排序消费
    var urgencyOverride: Bool?

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    var recurrence: RecurrenceRule? {
        get { recurrenceRaw.flatMap(RecurrenceRule.init(rawValue:)) }
        set { recurrenceRaw = newValue?.rawValue }
    }

    static let urgentWindow: TimeInterval = 48 * 3600   // 48 小时内(含逾期)视为紧急

    var isImportant: Bool { priority != .low }          // 高/中 = 重要

    func isUrgent(asOf now: Date = .now) -> Bool {
        if let o = urgencyOverride { return o }
        guard let d = deadline else { return false }
        return d <= now.addingTimeInterval(Self.urgentWindow)
    }

    init(title: String,
         notes: String = "",
         deadline: Date? = nil,
         priority: Priority = .medium,
         tags: [String] = [],
         recurrence: RecurrenceRule? = nil,
         urgencyOverride: Bool? = nil,
         createdAt: Date = .now,
         columnID: UUID? = nil,
         boardOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.deadline = deadline
        self.priorityRaw = priority.rawValue
        self.tags = tags
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = createdAt
        self.snoozedUntil = nil
        self.recurrenceRaw = recurrence?.rawValue
        self.columnID = columnID
        self.boardOrder = boardOrder
        self.urgencyOverride = urgencyOverride
    }
}
