import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct PlanStoreTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    @Test func dayPlanPersists() throws {
        let context = try makeContext()
        let plan = DayPlan(day: Date(timeIntervalSinceReferenceDate: 0), committedTaskIDs: [UUID()])
        context.insert(plan)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<DayPlan>()).count == 1)
    }

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
    }

    @Test func toggleAddsAndRemovesCommitment() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let task = TodoTask(title: "写周报")
        context.insert(task)

        store.toggle(task, on: day)
        #expect(store.isCommitted(task, on: day))
        store.toggle(task, on: day)
        #expect(!store.isCommitted(task, on: day))
    }

    @Test func ensurePlanReusesSameDayPlan() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 21))!
        _ = store.ensurePlan(on: morning)
        _ = store.ensurePlan(on: evening)
        #expect(try context.fetch(FetchDescriptor<DayPlan>()).count == 1)
    }

    @Test func committedTasksSkipsDeletedIDs() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let task = TodoTask(title: "活儿")
        context.insert(task)
        store.toggle(task, on: day)
        context.delete(task)
        #expect(store.committedTasks(on: day).isEmpty)   // ID 取不到 → 跳过,不崩
    }

    @Test func needsPlanningWhenNeverPlanned() {
        #expect(PlanStore.needsPlanning(lastPlanned: nil, now: day, calendar: calendar))
    }

    @Test func needsPlanningWhenLastPlannedYesterday() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        #expect(PlanStore.needsPlanning(lastPlanned: yesterday, now: day, calendar: calendar))
    }

    @Test func noPlanningWhenAlreadyPlannedToday() {
        let earlierToday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7))!
        #expect(!PlanStore.needsPlanning(lastPlanned: earlierToday, now: day, calendar: calendar))
    }

    @Test func carryOverCandidatesReturnsPriorUnfinished() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let done = TodoTask(title: "已完成"); done.isCompleted = true
        let pending = TodoTask(title: "未完成")
        context.insert(done); context.insert(pending)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        store.toggle(done, on: yesterday)
        store.toggle(pending, on: yesterday)
        let candidates = store.carryOverCandidates(before: day)
        #expect(candidates.map(\.id) == [pending.id])   // 已完成的不算,只返回未完成
    }

    @Test func carryOverCandidatesEmptyWhenNoPriorPlan() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let t = TodoTask(title: "今天才承诺"); context.insert(t)
        store.toggle(t, on: day)                         // 只有今天的 plan,无更早的
        #expect(store.carryOverCandidates(before: day).isEmpty)
    }
}
