import SwiftUI
import SwiftData

/// 开工规划:从活动任务里挑出「今日承诺」。逾期+今日到期者置顶高亮作为建议。
/// 不限数量、不拦截(只记录不干预)。确认后写 lastPlannedDay。
struct PlanningView: View {
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @AppStorage(AppSettings.Key.lastPlannedDay) private var lastPlannedDay = 0.0

    private var store: PlanStore { PlanStore(context: context) }
    private var now: Date { .now }

    /// 候选:未完成、未 snooze;逾期/今日到期排前,其余按优先级。
    private var candidates: [TodoTask] {
        let cal = Calendar.current
        return tasks
            .filter { !$0.isCompleted && ($0.snoozedUntil.map { $0 <= now } ?? true) }
            .sorted { lhs, rhs in
                let l = suggested(lhs, cal: cal), r = suggested(rhs, cal: cal)
                if l != r { return l }                       // 建议项在前
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
    }

    private func suggested(_ t: TodoTask, cal: Calendar) -> Bool {
        guard let d = t.deadline else { return false }
        return cal.isDateInToday(d) || d < now
    }

    private var committedCount: Int {
        store.plan(on: now)?.committedTaskIDs.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(candidates) { task in
                        row(task)
                    }
                }
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .padding(12)
            }
            .scrollEdgeFade()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("开工规划")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("已承诺 \(committedCount) 件")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button("开始今天") {
                lastPlannedDay = now.timeIntervalSinceReferenceDate
                try? context.save()
                onDone()
            }
            .buttonStyle(NoirPillButtonStyle(prominent: true))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func row(_ task: TodoTask) -> some View {
        let on = store.isCommitted(task, on: now)
        return Button {
            store.toggle(task, on: now)
            try? context.save()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.accent : Theme.textTertiary)
                Text(task.title)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if suggested(task, cal: .current) {
                    Text("建议")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
