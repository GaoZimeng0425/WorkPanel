import Foundation
import SwiftData

@MainActor
final class TagStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 全部标签,按 order 排序。
    func all() -> [Tag] {
        (try? context.fetch(
            FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.order)])
        )) ?? []
    }

    /// 注册标签:去空白;空串忽略;已存在返回现有,否则插入(order 追加末尾)。
    @discardableResult
    func register(_ name: String) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let existing = all()
        if let hit = existing.first(where: { $0.name == trimmed }) { return hit }
        let nextOrder = (existing.map(\.order).max() ?? -1) + 1
        let tag = Tag(name: trimmed, order: nextOrder)
        context.insert(tag)
        return tag
    }

    /// 批量注册(漏斗用)。
    func register(names: [String]) {
        for name in names { register(name) }
    }

    /// 删除标签:删 Tag 行 + 从所有任务移除该名字,然后 saveTracking。
    func delete(_ name: String) {
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        for task in tasks where task.tags.contains(name) {
            task.tags.removeAll { $0 == name }
        }
        for tag in all() where tag.name == name {
            context.delete(tag)
        }
        try? context.saveTracking()
    }

    /// 库里没有任何 Tag 时,从现有任务标签去重生成。否则不动。
    func seedFromTasksIfNeeded() {
        guard all().isEmpty else { return }
        let names = Set(((try? context.fetch(FetchDescriptor<TodoTask>())) ?? []).flatMap(\.tags))
        for name in names.sorted() { register(name) }
    }

    /// 确保每个任务标签名都在 store(merge 后调用)。既有标签与顺序不动。
    func reconcileFromTasks() {
        let names = Set(((try? context.fetch(FetchDescriptor<TodoTask>())) ?? []).flatMap(\.tags))
        let known = Set(all().map(\.name))
        for name in names.subtracting(known).sorted() { register(name) }
    }
}
