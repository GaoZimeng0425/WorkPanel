import Foundation

/// 复盘统计:从 [DayPlan] + 任务 completedAt 派生,无副作用、不依赖容器。
enum PlanStats {
    struct DayStat: Equatable {
        let day: Date
        let committed: Int
        let completed: Int
    }

    @MainActor
    private static func taskMap(_ tasks: [TodoTask]) -> [UUID: TodoTask] {
        Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// 某日承诺任务里,completedAt 落在该日的数量。
    @MainActor
    private static func completedCount(in plan: DayPlan,
                                       map: [UUID: TodoTask],
                                       calendar: Calendar) -> Int {
        plan.committedTaskIDs.reduce(0) { acc, id in
            guard let t = map[id], let done = t.completedAt,
                  calendar.isDate(done, inSameDayAs: plan.day) else { return acc }
            return acc + 1
        }
    }

    /// 每个 DayPlan 一条 DayStat,按 day 升序。
    @MainActor
    static func dayStats(plans: [DayPlan], tasks: [TodoTask], calendar: Calendar) -> [DayStat] {
        let map = taskMap(tasks)
        return plans.sorted { $0.day < $1.day }.map { plan in
            DayStat(day: plan.day,
                    committed: plan.committedTaskIDs.count,
                    completed: completedCount(in: plan, map: map, calendar: calendar))
        }
    }

    /// 顺延榜:被承诺、但当天未完成的天数 ≥2 的任务,按天数倒序。
    @MainActor
    static func carryOver(plans: [DayPlan], tasks: [TodoTask], calendar: Calendar)
        -> [(task: TodoTask, days: Int)] {
        let map = taskMap(tasks)
        var counts: [UUID: Int] = [:]
        for plan in plans {
            for id in plan.committedTaskIDs {
                let doneToday = map[id]?.completedAt.map { calendar.isDate($0, inSameDayAs: plan.day) } ?? false
                if !doneToday { counts[id, default: 0] += 1 }
            }
        }
        return counts
            .filter { $0.value >= 2 }
            .compactMap { id, n in map[id].map { (task: $0, days: n) } }
            .sorted { $0.days > $1.days }
    }

    /// 超载日:承诺数 − 完成数 ≥ threshold 的天数。
    @MainActor
    static func overloadDays(plans: [DayPlan], tasks: [TodoTask],
                             threshold: Int, calendar: Calendar) -> Int {
        let map = taskMap(tasks)
        return plans.reduce(0) { acc, plan in
            let gap = plan.committedTaskIDs.count - completedCount(in: plan, map: map, calendar: calendar)
            return acc + (gap >= threshold ? 1 : 0)
        }
    }
}
