import SwiftUI
import SwiftData

/// 今日承诺(承诺驱动):显示今天 DayPlan 里主动挑出的任务。
/// 空态引导开工规划;底部克制提示「今天到期但未纳入」的数量。
struct TodayLensView: View {
    var onPlan: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]

    private var store: PlanStore { PlanStore(context: context) }
    private var now: Date { .now }

    private var committed: [TodoTask] { store.committedTasks(on: now) }
    private var completedCount: Int { committed.filter(\.isCompleted).count }

    /// 今天到期/逾期但不在承诺集里的活动任务数。
    private var dueNotCommittedCount: Int {
        let cal = Calendar.current
        let ids = Set(committed.map(\.id))
        return tasks.filter { t in
            guard !t.isCompleted, !ids.contains(t.id), let d = t.deadline else { return false }
            return cal.isDateInToday(d) || d < now
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if committed.isEmpty {
                    emptyState
                } else {
                    HStack {
                        Text("承诺 \(committed.count) · 完成 \(completedCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("规划今天", action: onPlan)
                            .buttonStyle(NoirPillButtonStyle())
                    }
                    .padding(.horizontal, 4)
                    ForEach(committed) { LensCard(task: $0) }
                    if dueNotCommittedCount > 0 {
                        Text("另有 \(dueNotCommittedCount) 件今天到期未纳入")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .padding(12)
        }
        .scrollEdgeFade()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sunrise")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("还没规划今天")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Button("开工规划", action: onPlan)
                .buttonStyle(NoirPillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}
