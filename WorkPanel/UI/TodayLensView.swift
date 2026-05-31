import SwiftUI
import SwiftData

/// 今日聚焦(只读):逾期 + 今日到期(按 deadline)的活动任务,按截止时间升序。
struct TodayLensView: View {
    @Query private var tasks: [TodoTask]

    private var items: [TodoTask] {
        let now = Date.now
        let cal = Calendar.current
        return tasks
            .filter { task in
                guard !task.isCompleted, let d = task.deadline else { return false }
                return cal.isDateInToday(d) || d < now
            }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Text("今日无到期任务")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    ForEach(items) { LensCard(task: $0) }
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(12)
        }
        .scrollEdgeFade()
    }
}
