import SwiftUI
import SwiftData

/// 开工规划:从活动任务里挑出「今日承诺」。顺延项(昨天承诺未完成)置顶 + 「顺延」徽章;
/// 逾期/今日到期者标「建议」。不限数量、可跳过(只记录不干预,跳过则今天无 DayPlan)。
struct PlanningView: View {
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @AppStorage(AppSettings.Key.lastPlannedDay) private var lastPlannedDay = 0.0
    @State private var carriedIDs: Set<UUID> = []
    @State private var didLoadCarryOver = false

    private var store: PlanStore { PlanStore(context: context) }
    private var now: Date { .now }

    /// 候选:未完成、未 snooze;顺延项最前,建议项次之,其余按优先级。
    private var candidates: [TodoTask] {
        let cal = Calendar.current
        return tasks
            .filter { !$0.isCompleted && ($0.snoozedUntil.map { $0 <= now } ?? true) }
            .sorted { lhs, rhs in
                if lhs.planOrder != rhs.planOrder { return lhs.planOrder < rhs.planOrder }
                let lc = carriedIDs.contains(lhs.id), rc = carriedIDs.contains(rhs.id)
                if lc != rc { return lc }
                let ls = suggested(lhs, cal: cal), rs = suggested(rhs, cal: cal)
                if ls != rs { return ls }
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
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, task in
                        row(task)
                            .draggable(task.id.uuidString)
                            .deferredDrop { dropReorder($0, before: index) }
                    }
                }
                .deferredDrop { dropReorder($0, before: candidates.count) }
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .padding(12)
            }
            .scrollEdgeFade()
        }
        .onAppear {
            guard !didLoadCarryOver else { return }
            didLoadCarryOver = true
            carriedIDs = Set(store.carryOverCandidates(before: now).map(\.id))   // 只读:标记顺延,不自动勾选
        }
    }

    /// 跳过与「开始今天」都只标记 lastPlannedDay 并收起;承诺与否取决于用户是否点选过行(实时写入)。
    private func dismiss() {
        lastPlannedDay = now.timeIntervalSinceReferenceDate
        try? context.save()
        onDone()
    }

    private func dropReorder(_ payload: String, before index: Int) {
        guard let id = UUID(uuidString: payload) else { return }
        store.reorderPlan(candidates.map(\.id), move: id, before: index)
        try? context.save()
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
            Button("跳过", action: dismiss)
                .buttonStyle(NoirPillButtonStyle())
            Button("开始今天", action: dismiss)
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
                if carriedIDs.contains(task.id) {
                    Text("顺延")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.recurrence)
                } else if suggested(task, cal: .current) {
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
