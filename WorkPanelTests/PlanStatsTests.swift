import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct PlanStatsTests {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private func d(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    // 周一承诺 A、B,只 A 当天完成 → committed 2 / completed 1
    @Test func dayStatsCountsCommittedAndCompletedSameDay() {
        let a = TodoTask(title: "A"); a.isCompleted = true; a.completedAt = d(1, 14)
        let b = TodoTask(title: "B")
        let plan = DayPlan(day: calendar.startOfDay(for: d(1)),
                           committedTaskIDs: [a.id, b.id])
        let stats = PlanStats.dayStats(plans: [plan], tasks: [a, b], calendar: calendar)
        #expect(stats.count == 1)
        #expect(stats[0].committed == 2)
        #expect(stats[0].completed == 1)
    }

    // 任务在周一/周二被承诺都没当天完成 → 顺延 2 天
    @Test func carryOverCountsRepeatedlyCommittedUnfinished() {
        let t = TodoTask(title: "拖延王")
        let p1 = DayPlan(day: calendar.startOfDay(for: d(1)), committedTaskIDs: [t.id])
        let p2 = DayPlan(day: calendar.startOfDay(for: d(2)), committedTaskIDs: [t.id])
        let out = PlanStats.carryOver(plans: [p1, p2], tasks: [t], calendar: calendar)
        #expect(out.count == 1)
        #expect(out[0].task.id == t.id)
        #expect(out[0].days == 2)
    }

    // 只承诺 1 天的不进顺延榜
    @Test func carryOverExcludesSingleDay() {
        let t = TodoTask(title: "一次性")
        let p1 = DayPlan(day: calendar.startOfDay(for: d(1)), committedTaskIDs: [t.id])
        #expect(PlanStats.carryOver(plans: [p1], tasks: [t], calendar: calendar).isEmpty)
    }

    // 承诺 4 完成 1 → 差 3 ≥ 阈值 3 → 超载日 +1
    @Test func overloadDaysCountsHighGap() {
        let tasks = (0..<4).map { TodoTask(title: "T\($0)") }
        tasks[0].isCompleted = true; tasks[0].completedAt = d(1, 15)
        let plan = DayPlan(day: calendar.startOfDay(for: d(1)),
                           committedTaskIDs: tasks.map(\.id))
        let n = PlanStats.overloadDays(plans: [plan], tasks: tasks, threshold: 3, calendar: calendar)
        #expect(n == 1)
    }
}
