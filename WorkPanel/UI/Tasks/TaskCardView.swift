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
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Theme.success : Theme.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            StatusDot(color: Theme.priority(task.priority),
                      glow: task.priority == .high)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: Theme.titleFontSize))
                    .foregroundStyle(task.isCompleted ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(Theme.priorityLabel(task.priority))
                        .noirBadge(Theme.priority(task.priority))
                        .lineLimit(1)
                    if let d = task.deadline {
                        Text(Calendar.current.isDateInToday(d)
                             ? d.formatted(date: .omitted, time: .shortened)
                             : d.formatted(.dateTime.month().day()))
                            .noirBadge(d < .now ? Theme.priority(.high) : Theme.deadline)
                            .lineLimit(1)
                    }
                    if let rule = task.recurrence {
                        Label(Theme.recurrenceLabel(rule), systemImage: "repeat")
                            .labelStyle(.titleAndIcon)
                            .noirBadge(Theme.recurrence)
                            .lineLimit(1)
                    }
                    ForEach(Array(task.tags.prefix(2)), id: \.self) { tag in
                        Text("#\(tag)").noirBadge(Theme.tag)
                            .lineLimit(1)
                    }
                    if task.tags.count > 2 {
                        Text("+\(task.tags.count - 2)")
                            .noirBadge(Theme.textTertiary)
                            .lineLimit(1)
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
