import SwiftUI
import SwiftData

/// 优先级透镜:高/中/低 三列,拖拽卡片到某列即设 priority。
struct PriorityLensView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]

    private var store: BoardStore { BoardStore(context: context) }

    private func items(_ p: Priority) -> [TodoTask] {
        tasks.filter { !$0.isCompleted && $0.priority == p }
             .sorted { $0.boardOrder < $1.boardOrder }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(.high)
            column(.medium)
            column(.low)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func column(_ p: Priority) -> some View {
        let list = items(p)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StatusDot(color: Theme.priority(p), glow: p == .high, size: 8)
                Text(Theme.priorityLabel(p))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(list.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(list) { LensCard(task: $0, draggable: true) }
                }
            }
            .scrollEdgeFade()
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .noirColumn()
        .deferredDrop { payload in
            guard let id = UUID(uuidString: payload),
                  let task = tasks.first(where: { $0.id == id }) else { return }
            store.setPriority(task, to: p)
            try? context.save()
        }
    }
}
