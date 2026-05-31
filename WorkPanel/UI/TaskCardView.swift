import SwiftUI

/// 看板与 TODO 列表共用的任务卡片。仅负责外观;
/// 菜单 / 拖拽 / contextMenu 等行为由调用方在 `trailing` 槽或外层修饰符注入。
struct TaskCardView<Trailing: View>: View {
    let task: TodoTask
    let onComplete: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.borderless)

            StatusDot(color: Theme.priority(task.priority),
                      glow: task.priority == .high)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: Theme.titleFontSize))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let d = task.deadline {
                        Text(d.formatted(date: .omitted, time: .shortened))
                            .noirBadge(d < .now ? Theme.priority(.high) : Theme.deadline)
                    }
                    if let rule = task.recurrence {
                        Label(Theme.recurrenceLabel(rule), systemImage: "repeat")
                            .labelStyle(.titleAndIcon)
                            .noirBadge(Theme.recurrence)
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text("#\(tag)").noirBadge(Theme.tag)
                    }
                }
            }

            Spacer(minLength: 0)
            trailing()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noirCard()
    }
}
