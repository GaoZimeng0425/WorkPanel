import Foundation

struct WorkColumn: Equatable, Sendable {
    nonisolated let id: UUID
    nonisolated var name: String
}

struct WorkTaskSnapshot: Equatable, Sendable {
    nonisolated let id: UUID
    nonisolated var title: String
    nonisolated var notes: String
    nonisolated var priority: Priority
    nonisolated var tags: [String]
    nonisolated var columnID: UUID?
    nonisolated var boardOrder: Int
}

/// 全量编辑器的文档层:序列化 / 行解析 / 编辑锚点平移 / 对账。纯函数,脱离 UI 与 SwiftData。
enum WorkDocument {
    nonisolated static let uncategorizedHeading = "未分类"

    struct Anchor: Equatable, Sendable {
        nonisolated let id: UUID
        nonisolated var offset: Int
    }

    nonisolated static func serialize(columns: [WorkColumn],
                                      tasks: [WorkTaskSnapshot]) -> (text: String, anchors: [Anchor]) {
        var text = ""
        var anchors: [Anchor] = []

        func emitGroup(heading: String, items: [WorkTaskSnapshot]) {
            if !text.isEmpty { text += "\n" }          // 组与组之间空一行
            text += "## " + heading + "\n"
            for task in items.sorted(by: { $0.boardOrder < $1.boardOrder }) {
                anchors.append(Anchor(id: task.id, offset: text.count))   // '-' 的偏移
                text += "- [ ] " + itemLine(task) + "\n"
                if !task.notes.isEmpty {                       // 空备注不输出缩进空行
                    for noteLine in task.notes.split(separator: "\n", omittingEmptySubsequences: false) {
                        text += "    " + noteLine + "\n"
                    }
                }
            }
        }

        for col in columns {
            let items = tasks.filter { $0.columnID == col.id }
            guard !items.isEmpty else { continue }
            emitGroup(heading: col.name, items: items)
        }
        let orphans = tasks.filter { $0.columnID == nil }
        if !orphans.isEmpty { emitGroup(heading: uncategorizedHeading, items: orphans) }

        if text.hasSuffix("\n") { text.removeLast() }   // 去掉末尾换行,文档更干净
        return (text, anchors)
    }

    nonisolated private static func itemLine(_ task: WorkTaskSnapshot) -> String {
        var parts = [task.title]
        switch task.priority {
        case .high: parts.append("!高")
        case .low:  parts.append("!低")
        case .medium: break                              // medium 不输出 token
        }
        parts.append(contentsOf: task.tags.map { "#" + $0 })
        return parts.joined(separator: " ")
    }
}
