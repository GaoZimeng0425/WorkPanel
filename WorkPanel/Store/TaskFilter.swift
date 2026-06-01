import Foundation

enum TaskFilter {
    static func today(_ tasks: [TodoTask], now: Date, calendar: Calendar = .current) -> [TodoTask] {
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        return tasks
            .filter { task in
                !task.isCompleted
                && (task.snoozedUntil.map { $0 <= now } ?? true)
                && (task.deadline.map { $0 <= endOfToday } ?? false)
            }
            .sorted(by: sortRule)
    }

    static func upcoming(_ tasks: [TodoTask], now: Date, calendar: Calendar = .current) -> [TodoTask] {
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        return tasks
            .filter { !$0.isCompleted && ($0.deadline.map { $0 > endOfToday } ?? false) }
            .sorted(by: sortRule)
    }

    static func all(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { !$0.isCompleted }.sorted(by: sortRule)
    }

    static func archived(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    static func sortRule(_ a: TodoTask, _ b: TodoTask) -> Bool {
        if a.priority.rawValue != b.priority.rawValue {
            return a.priority.rawValue > b.priority.rawValue
        }
        switch (a.deadline, b.deadline) {
        case let (x?, y?): return x < y
        case (nil, _?):    return false
        case (_?, nil):    return true
        case (nil, nil):   return a.createdAt < b.createdAt
        }
    }
}
