import SwiftUI
import SwiftData

/// 复盘(只读):本周承诺 vs 完成、顺延榜、超载天数。只报事实,不评判。
struct ReviewLensView: View {
    private static let overloadThreshold = 3

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query private var plans: [DayPlan]

    private var calendar: Calendar { .current }
    private var now: Date { .now }

    /// 最近 7 个自然日内的 DayPlan。
    private var weekPlans: [DayPlan] {
        guard let from = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        else { return [] }
        return plans.filter { $0.day >= from }
    }

    private var dayStats: [PlanStats.DayStat] {
        PlanStats.dayStats(plans: weekPlans, tasks: tasks, calendar: calendar)
    }
    private var carryOver: [(task: TodoTask, days: Int)] {
        PlanStats.carryOver(plans: weekPlans, tasks: tasks, calendar: calendar)
    }
    private var overloadDays: Int {
        PlanStats.overloadDays(plans: weekPlans, tasks: tasks,
                               threshold: Self.overloadThreshold, calendar: calendar)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("本周 · 承诺 vs 完成") {
                    if dayStats.isEmpty {
                        Text("本周还没有规划记录")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    } else {
                        ForEach(dayStats, id: \.day) { s in
                            HStack {
                                Text(Self.dayFormatter.string(from: s.day))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary).frame(width: 44, alignment: .leading)
                                Text("承诺 \(s.committed)").foregroundStyle(Theme.textSecondary)
                                Text("完成 \(s.completed)").foregroundStyle(Theme.accent)
                                Spacer()
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                section("顺延榜") {
                    if carryOver.isEmpty {
                        Text("没有反复顺延的任务")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    } else {
                        ForEach(carryOver, id: \.task.id) { item in
                            HStack {
                                Text(item.task.title).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Spacer()
                                Text("顺延 \(item.days) 天").foregroundStyle(Theme.textTertiary)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                section("超载天数") {
                    Text("\(overloadDays) 天承诺远多于完成")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .scrollEdgeFade()
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
    }
}
