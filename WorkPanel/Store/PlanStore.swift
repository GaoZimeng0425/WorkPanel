import Foundation
import SwiftData

@MainActor
final class PlanStore {
    let context: ModelContext
    let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// 返回 day 所在自然日的 DayPlan(若有)。谓词无法表达 calendar 比较,内存过滤(N 小)。
    func plan(on day: Date) -> DayPlan? {
        let all = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        return all.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// 取或建 day 当天的 DayPlan,day 归一化到 00:00。
    @discardableResult
    func ensurePlan(on day: Date) -> DayPlan {
        if let p = plan(on: day) { return p }
        let p = DayPlan(day: calendar.startOfDay(for: day))
        context.insert(p)
        return p
    }

    func isCommitted(_ task: TodoTask, on day: Date) -> Bool {
        plan(on: day)?.committedTaskIDs.contains(task.id) ?? false
    }

    /// 切换 task 在 day 的承诺状态。
    func toggle(_ task: TodoTask, on day: Date) {
        let p = ensurePlan(on: day)
        if let idx = p.committedTaskIDs.firstIndex(of: task.id) {
            p.committedTaskIDs.remove(at: idx)
        } else {
            p.committedTaskIDs.append(task.id)
        }
    }

    /// day 当天承诺的任务(按承诺顺序;已删除的 ID 跳过)。
    func committedTasks(on day: Date) -> [TodoTask] {
        guard let p = plan(on: day) else { return [] }
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return p.committedTaskIDs.compactMap { byID[$0] }
    }

    /// 严格早于 day 的「最近一条」DayPlan 里、至今仍未完成的承诺任务(顺延候选)。只读,不写库。
    func carryOverCandidates(before day: Date) -> [TodoTask] {
        let start = calendar.startOfDay(for: day)
        let plans = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        guard let prev = plans.filter({ $0.day < start }).max(by: { $0.day < $1.day })
        else { return [] }
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return prev.committedTaskIDs.compactMap { byID[$0] }.filter { !$0.isCompleted }
    }

    /// 是否该触发开工规划:从未规划过,或上次规划不在今天。
    nonisolated static func needsPlanning(lastPlanned: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastPlanned else { return true }
        return !calendar.isDate(lastPlanned, inSameDayAs: now)
    }
}
