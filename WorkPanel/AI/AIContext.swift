import Foundation

/// 把任务渲染成喂给 LLM 的 user message 文本。
enum AIContext {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

    /// 单个任务:标题/优先级/截止/标签/备注。
    static func renderTask(_ task: TodoTask) -> String {
        var lines: [String] = []
        lines.append("标题: \(task.title)")
        lines.append("优先级: \(Theme.priorityLabel(task.priority))")
        if let d = task.deadline {
            lines.append("截止: \(dateFormatter.string(from: d))")
        }
        if !task.tags.isEmpty {
            lines.append("标签: " + task.tags.map { "#\($0)" }.joined(separator: " "))
        }
        let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("备注:")
        lines.append(notes.isEmpty ? "(无)" : notes)
        return lines.joined(separator: "\n")
    }

    /// 所有未完成任务的要点列表。
    static func renderInProgress(_ tasks: [TodoTask]) -> String {
        let pending = tasks.filter { !$0.isCompleted }
        guard !pending.isEmpty else { return "(当前没有进行中的任务)" }
        return pending.map { t in
            var line = "- [\(Theme.priorityLabel(t.priority))] \(t.title)"
            if let d = t.deadline {
                line += " (截止 \(dateFormatter.string(from: d)))"
            }
            if !t.tags.isEmpty {
                line += " " + t.tags.map { "#\($0)" }.joined(separator: " ")
            }
            return line
        }.joined(separator: "\n")
    }
}
