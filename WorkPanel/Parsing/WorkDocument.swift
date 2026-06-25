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

        // 嵌套于 MainActor 隔离的 enum 内,合成的 Equatable 会带 MainActor 隔离,nonisolated 上下文无法用;故手写 nonisolated ==(新增字段时记得同步比较)。
        nonisolated static func == (lhs: Anchor, rhs: Anchor) -> Bool {
            lhs.id == rhs.id && lhs.offset == rhs.offset
        }
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

    struct Edit: Equatable, Sendable {
        nonisolated var loc: Int
        nonisolated var oldLen: Int
        nonisolated var newLen: Int

        // 嵌套于 MainActor 隔离的 enum 内,合成的 Equatable 会带 MainActor 隔离,nonisolated 上下文无法用;故手写 nonisolated ==(新增字段时记得同步比较)。
        nonisolated static func == (lhs: Edit, rhs: Edit) -> Bool {
            lhs.loc == rhs.loc && lhs.oldLen == rhs.oldLen && lhs.newLen == rhs.newLen
        }
    }

    /// 单段编辑检测:公共前缀长度 = loc,公共后缀长度从两端各扣除 loc 之后取。
    nonisolated static func computeEdit(old: [Character], new: [Character]) -> Edit {
        var p = 0
        let minLen = min(old.count, new.count)
        while p < minLen && old[p] == new[p] { p += 1 }
        var s = 0
        while s < (minLen - p) && old[old.count - 1 - s] == new[new.count - 1 - s] { s += 1 }
        return Edit(loc: p, oldLen: old.count - p - s, newLen: new.count - p - s)
    }

    nonisolated static func shift(anchors: [Anchor], by edit: Edit) -> [Anchor] {
        let delta = edit.newLen - edit.oldLen
        let regionEnd = edit.loc + edit.oldLen
        return anchors.compactMap { a in
            if a.offset >= regionEnd { return Anchor(id: a.id, offset: a.offset + delta) }
            if a.offset < edit.loc { return a }
            return nil                                   // 落在删除区间内 → 溶解
        }
    }

    struct Block: Equatable, Sendable {
        nonisolated var columnID: UUID?
        nonisolated var title: String
        nonisolated var priority: Priority?
        nonisolated var tags: [String]
        nonisolated var notes: String
        nonisolated var completed: Bool
        nonisolated var offset: Int

        // 嵌套于 MainActor 隔离的 enum 内,合成的 Equatable 会带 MainActor 隔离,nonisolated 上下文无法用;故手写 nonisolated ==(新增字段时记得同步比较)。
        nonisolated static func == (lhs: Block, rhs: Block) -> Bool {
            lhs.columnID == rhs.columnID && lhs.title == rhs.title &&
            lhs.priority == rhs.priority && lhs.tags == rhs.tags &&
            lhs.notes == rhs.notes && lhs.completed == rhs.completed &&
            lhs.offset == rhs.offset
        }
    }

    nonisolated static func parse(text: String, columns: [WorkColumn]) -> [Block] {
        var blocks: [Block] = []
        var currentColumn: UUID? = nil
        var offset = 0
        var noteLines: [String] = []                     // 累积当前块的 notes

        func flushNotes() {
            if !blocks.isEmpty {
                blocks[blocks.count - 1].notes = noteLines.joined(separator: "\n")
            }
            noteLines = []
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let lineStart = offset
            offset += line.count + 1                      // +1 = 换行符;末行多算 1 无妨

            if line.hasPrefix("## ") {
                flushNotes()
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentColumn = columns.first { $0.name == name }?.id
            } else if let rest = itemBody(line) {
                flushNotes()
                let parsed = WorkLine.parse(rest.text)
                blocks.append(Block(columnID: currentColumn,
                                    title: parsed.title, priority: parsed.priority, tags: parsed.tags,
                                    notes: "", completed: rest.completed, offset: lineStart))
            } else if let first = line.first, first == " " || first == "\t" {
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if !trimmed.isEmpty { noteLines.append(String(trimmed)) }
            }
            // 其余(空行 / 无缩进杂行)忽略
        }
        flushNotes()
        return blocks
    }

    /// 识别 `- [ ] x` / `- [x] x` / `- [X] x`,返回正文与勾选态;非条目行返回 nil。
    nonisolated private static func itemBody(_ line: String) -> (text: String, completed: Bool)? {
        for (prefix, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] {
            if line.hasPrefix(prefix) { return (String(line.dropFirst(prefix.count)), done) }
        }
        return nil
    }

    struct CreateSpec: Equatable, Sendable {
        nonisolated var title: String
        nonisolated var notes: String
        nonisolated var priority: Priority
        nonisolated var tags: [String]
        nonisolated var columnID: UUID?
        nonisolated var order: Int

        // 嵌套于 MainActor 隔离的 enum 内,合成的 Equatable 会带 MainActor 隔离,nonisolated 上下文无法用;故手写 nonisolated ==(新增字段时记得同步比较)。
        nonisolated static func == (lhs: CreateSpec, rhs: CreateSpec) -> Bool {
            lhs.title == rhs.title && lhs.notes == rhs.notes &&
            lhs.priority == rhs.priority && lhs.tags == rhs.tags &&
            lhs.columnID == rhs.columnID && lhs.order == rhs.order
        }
    }

    struct UpdateSpec: Equatable, Sendable {
        nonisolated var id: UUID
        nonisolated var title: String
        nonisolated var notes: String
        nonisolated var priority: Priority
        nonisolated var tags: [String]
        nonisolated var columnID: UUID?
        nonisolated var order: Int
        nonisolated var complete: Bool

        // 嵌套于 MainActor 隔离的 enum 内,合成的 Equatable 会带 MainActor 隔离,nonisolated 上下文无法用;故手写 nonisolated ==(新增字段时记得同步比较)。
        nonisolated static func == (lhs: UpdateSpec, rhs: UpdateSpec) -> Bool {
            lhs.id == rhs.id && lhs.title == rhs.title && lhs.notes == rhs.notes &&
            lhs.priority == rhs.priority && lhs.tags == rhs.tags &&
            lhs.columnID == rhs.columnID && lhs.order == rhs.order && lhs.complete == rhs.complete
        }
    }

    struct ChangeSet: Equatable, Sendable {
        nonisolated var creates: [CreateSpec]
        nonisolated var updates: [UpdateSpec]
        nonisolated var deletes: [UUID]

        // 嵌套于 MainActor 隔离的 enum 内,合成的 Equatable 会带 MainActor 隔离,nonisolated 上下文无法用;故手写 nonisolated ==(新增字段时记得同步比较)。
        nonisolated static func == (lhs: ChangeSet, rhs: ChangeSet) -> Bool {
            lhs.creates == rhs.creates && lhs.updates == rhs.updates && lhs.deletes == rhs.deletes
        }
    }

    nonisolated static func reconcile(blocks: [Block], anchors: [Anchor],
                                      liveTasks: [WorkTaskSnapshot]) -> ChangeSet {
        let liveByID = Dictionary(uniqueKeysWithValues: liveTasks.map { ($0.id, $0) })
        let idByOffset = Dictionary(anchors.map { ($0.offset, $0.id) }, uniquingKeysWith: { a, _ in a })

        var creates: [CreateSpec] = []
        var updates: [UpdateSpec] = []
        var matched: Set<UUID> = []
        var orderByColumn: [UUID?: Int] = [:]                 // 每列(含 nil)文档顺序计数

        for block in blocks {
            guard !block.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let order = orderByColumn[block.columnID, default: 0]
            orderByColumn[block.columnID] = order + 1

            if let id = idByOffset[block.offset], let live = liveByID[id] {
                matched.insert(id)
                updates.append(UpdateSpec(
                    id: id,
                    title: block.title.trimmingCharacters(in: .whitespaces),
                    notes: block.notes,
                    priority: block.priority ?? live.priority,                 // 缺省保留
                    tags: block.tags.isEmpty ? live.tags : block.tags,          // 缺省保留
                    columnID: block.columnID, order: order, complete: block.completed))
            } else {
                creates.append(CreateSpec(
                    title: block.title.trimmingCharacters(in: .whitespaces),
                    notes: block.notes,
                    priority: block.priority ?? .medium,
                    tags: block.tags,
                    columnID: block.columnID, order: order))
            }
        }
        let deletes = liveTasks.map(\.id).filter { !matched.contains($0) }
        return ChangeSet(creates: creates, updates: updates, deletes: deletes)
    }
}
