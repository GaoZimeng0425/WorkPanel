import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct TodoStoreTests {
    private var calendar = Calendar(identifier: .gregorian)
    private func makeStore() throws -> TodoStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, configurations: config)
        return TodoStore(context: ModelContext(container))
    }

    @Test func addInsertsTask() throws {
        let store = try makeStore()
        var parsed = ParsedInput()
        parsed.title = "写周报"
        parsed.priority = .high
        let task = store.add(parsed, notes: "三个项目进度")
        try store.context.save()
        #expect(task.title == "写周报")
        #expect(task.notes == "三个项目进度")
        #expect(try store.context.fetch(FetchDescriptor<TodoTask>()).count == 1)
    }

    @Test func completeNonRecurringSetsFlags() throws {
        let store = try makeStore()
        let task = TodoTask(title: "活儿")
        store.context.insert(task)
        let now = Date()
        store.complete(task, now: now)
        #expect(task.isCompleted)
        #expect(task.completedAt == now)
        #expect(try store.context.fetch(FetchDescriptor<TodoTask>()).count == 1)
    }

    @Test func completeRecurringSpawnsNextOccurrence() throws {
        let store = try makeStore()
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let task = TodoTask(title: "周会", deadline: deadline, recurrence: .weekly)
        store.context.insert(task)
        store.complete(task, now: Date())

        let all = try store.context.fetch(FetchDescriptor<TodoTask>())
        #expect(all.count == 2)
        let next = all.first { !$0.isCompleted }
        #expect(next != nil)
        let nextDay = calendar.dateComponents([.day], from: next!.deadline!).day
        #expect(nextDay == 8) // +7 days
        #expect(next?.recurrence == .weekly)
    }

    @Test func snoozeSetsDate() throws {
        let store = try makeStore()
        let task = TodoTask(title: "活儿")
        store.context.insert(task)
        let until = Date().addingTimeInterval(86_400)
        store.snooze(task, until: until)
        #expect(task.snoozedUntil == until)
    }

    @Test func todayFilterExcludesCompletedSnoozedAndFuture() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
        let dueToday = TodoTask(title: "今天", deadline: cal.date(byAdding: .hour, value: 2, to: now))
        let dueTomorrow = TodoTask(title: "明天", deadline: cal.date(byAdding: .day, value: 1, to: now))
        let done = TodoTask(title: "已完成", deadline: now); done.isCompleted = true
        let snoozed = TodoTask(title: "推迟", deadline: now)
        snoozed.snoozedUntil = cal.date(byAdding: .day, value: 1, to: now)

        let today = TaskFilter.today([dueToday, dueTomorrow, done, snoozed], now: now, calendar: cal)
        #expect(today.map(\.title) == ["今天"])
    }

    @Test func sortRanksHighPriorityThenEarlierDeadline() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
        let lowEarly = TodoTask(title: "低早", deadline: now, priority: .low)
        let highLate = TodoTask(title: "高晚",
                                deadline: cal.date(byAdding: .day, value: 1, to: now),
                                priority: .high)
        let sorted = TaskFilter.all([lowEarly, highLate])
        #expect(sorted.map(\.title) == ["高晚", "低早"])
    }
}
