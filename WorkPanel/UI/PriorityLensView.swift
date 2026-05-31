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
                Circle().fill(Theme.priority(p)).frame(width: 8, height: 8)
                Text(Theme.priorityLabel(p)).font(.subheadline).bold()
                Text("\(list.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
            }
            ForEach(list) { LensCard(task: $0, draggable: true) }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { dropped, _ in
            guard let s = dropped.first, let id = UUID(uuidString: s),
                  let task = tasks.first(where: { $0.id == id }) else { return false }
            // 推迟到系统拖拽影像淡出之后(~0.3s)再落位,避免残留(同 KanbanLensView)。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    store.setPriority(task, to: p)
                }
                try? context.save()
            }
            return true
        }
    }
}
