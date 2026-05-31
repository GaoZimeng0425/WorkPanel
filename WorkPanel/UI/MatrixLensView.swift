import SwiftUI
import SwiftData

/// 艾森豪威尔四象限(只读):按 (重要, 紧急) 把活动任务分到 4 格,点击卡片走编辑器。
/// 象限标题已自述两轴(如「重要 · 紧急」),故不再单独画边轴标签。
struct MatrixLensView: View {
    @Query private var tasks: [TodoTask]

    private var active: [TodoTask] { tasks.filter { !$0.isCompleted } }

    private func bucket(important: Bool, urgent: Bool) -> [TodoTask] {
        active.filter { $0.isImportant == important && $0.isUrgent() == urgent }
              .sorted { $0.boardOrder < $1.boardOrder }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                quadrant(important: true,  urgent: true,  action: "马上做")
                quadrant(important: true,  urgent: false, action: "计划做")
            }
            HStack(spacing: 10) {
                quadrant(important: false, urgent: true,  action: "尽快处理")
                quadrant(important: false, urgent: false, action: "有空再说")
            }
        }
        .padding(12)
    }

    private func quadrant(important: Bool, urgent: Bool, action: String) -> some View {
        let items = bucket(important: important, urgent: urgent)
        let color = Theme.quadrant(important: important, urgent: urgent)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title(important: important, urgent: urgent))
                    .font(.subheadline).bold().foregroundStyle(color)
                Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Text(action).font(.caption).foregroundStyle(.secondary)
            }
            Rectangle().fill(color.opacity(0.4)).frame(height: 1)
            ScrollView {
                VStack(spacing: 8) {
                    if items.isEmpty {
                        Text("空").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(items) { LensCard(task: $0) }
                    }
                }
            }
            .scrollEdgeFade()
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func title(important: Bool, urgent: Bool) -> String {
        switch (important, urgent) {
        case (true, true):   "重要 · 紧急"
        case (true, false):  "重要 · 不紧急"
        case (false, true):  "不重要 · 紧急"
        case (false, false): "不重要 · 不紧急"
        }
    }
}
