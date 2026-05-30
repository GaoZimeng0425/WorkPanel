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

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    var recurrence: RecurrenceRule? {
        get { recurrenceRaw.flatMap(RecurrenceRule.init(rawValue:)) }
        set { recurrenceRaw = newValue?.rawValue }
    }

    init(title: String,
         notes: String = "",
         deadline: Date? = nil,
         priority: Priority = .medium,
         tags: [String] = [],
         recurrence: RecurrenceRule? = nil,
         createdAt: Date = .now) {
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
    }
}
