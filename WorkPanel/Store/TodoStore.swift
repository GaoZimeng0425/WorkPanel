import Foundation
import SwiftData

@MainActor
final class TodoStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func add(_ parsed: ParsedInput, notes: String, now: Date = .now) -> TodoTask {
        let task = TodoTask(title: parsed.title,
                            notes: notes,
                            deadline: parsed.deadline,
                            priority: parsed.priority,
                            tags: parsed.tags,
                            recurrence: parsed.recurrence,
                            urgencyOverride: parsed.urgencyOverride,
                            createdAt: now)
        context.insert(task)
        return task
    }

    /// Marks `task` complete. If it recurs, inserts and returns the next occurrence (so the
    /// caller can schedule its reminder); otherwise returns nil.
    @discardableResult
    func complete(_ task: TodoTask, now: Date = .now, calendar: Calendar = .current) -> TodoTask? {
        var follow: TodoTask?
        if let rule = task.recurrence,
           let next = Self.nextDeadline(after: task.deadline ?? now, rule: rule, calendar: calendar) {
            let occurrence = TodoTask(title: task.title,
                                      notes: task.notes,
                                      deadline: next,
                                      priority: task.priority,
                                      tags: task.tags,
                                      recurrence: rule,
                                      urgencyOverride: task.urgencyOverride,
                                      createdAt: now)
            context.insert(occurrence)
            follow = occurrence
        }
        task.isCompleted = true
        task.completedAt = now
        return follow
    }

    func reopen(_ task: TodoTask) {
        task.isCompleted = false
        task.completedAt = nil
        task.snoozedUntil = nil
    }

    func snooze(_ task: TodoTask, until date: Date) {
        task.snoozedUntil = date
    }

    func delete(_ task: TodoTask, now: Date = .now) {
        context.delete(task)
    }

    static func nextDeadline(after date: Date, rule: RecurrenceRule, calendar: Calendar) -> Date? {
        switch rule {
        case .daily:   return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:  return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date)!
            var wd = calendar.component(.weekday, from: d)
            while wd == 1 || wd == 7 { // skip Sunday/Saturday
                d = calendar.date(byAdding: .day, value: 1, to: d)!
                wd = calendar.component(.weekday, from: d)
            }
            return d
        }
    }
}
