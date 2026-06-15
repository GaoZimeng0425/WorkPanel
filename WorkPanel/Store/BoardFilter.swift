import Foundation
import Observation

/// 看板共享过滤器:跨透镜筛选任务。条件不持久化(随 BoardView 重建清空)。
/// 维度之间是 AND;同一维度内是 OR。Review 透镜不消费本对象。
@Observable
final class BoardFilter {
    var searchText: String = ""
    var tags: Set<String> = []
    var priorities: Set<Priority> = []
    var urgentOnly: Bool = false

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    var isActive: Bool {
        !trimmedSearch.isEmpty || !tags.isEmpty || !priorities.isEmpty || urgentOnly
    }

    /// 只过滤,不排序、不剔除已完成——是否排除 completed 由各透镜自行决定。
    func apply(_ tasks: [TodoTask], asOf now: Date = .now) -> [TodoTask] {
        guard isActive else { return tasks }
        let q = trimmedSearch
        return tasks.filter { t in
            if !q.isEmpty,
               !t.title.localizedCaseInsensitiveContains(q),
               !t.notes.localizedCaseInsensitiveContains(q) { return false }
            if !tags.isEmpty, tags.isDisjoint(with: t.tags) { return false }
            if !priorities.isEmpty, !priorities.contains(t.priority) { return false }
            if urgentOnly, !t.isUrgent(asOf: now) { return false }
            return true
        }
    }

    func clear() {
        searchText = ""
        tags = []
        priorities = []
        urgentOnly = false
    }
}
