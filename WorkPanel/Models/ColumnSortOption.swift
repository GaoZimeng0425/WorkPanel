import Foundation

/// 看板列内任务的排序选项。rawValue 用于按列持久化排序设置。
enum ColumnSortOption: String, CaseIterable, Identifiable {
    case manual, priority, deadline, createdAt, title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:    "手动"
        case .priority:  "优先级"
        case .deadline:  "截止日期"
        case .createdAt: "创建时间"
        case .title:     "标题"
        }
    }

    /// nil 或未知字符串一律回退手动排序。
    static func from(raw: String?) -> ColumnSortOption {
        raw.flatMap(ColumnSortOption.init(rawValue:)) ?? .manual
    }

    /// 按当前规则排序;主键无定论时统一以 boardOrder 升序决胜,不依赖 sorted 的稳定性。
    func sorted(_ tasks: [TodoTask]) -> [TodoTask] {
        switch self {
        case .manual:
            return tasks.sorted { $0.boardOrder < $1.boardOrder }
        case .priority:
            return tasks.sorted { compare($0, $1) { a, b in
                a.priorityRaw == b.priorityRaw ? nil : a.priorityRaw > b.priorityRaw
            } }
        case .deadline:
            return tasks.sorted { compare($0, $1) { a, b in
                switch (a.deadline, b.deadline) {
                case let (x?, y?): return x == y ? nil : x < y   // 近的在前,相同交决胜
                case (nil, _?):    return false   // 无截止殿后
                case (_?, nil):    return true
                case (nil, nil):   return nil     // 交给 boardOrder 决胜
                }
            } }
        case .createdAt:
            return tasks.sorted { compare($0, $1) { a, b in
                a.createdAt == b.createdAt ? nil : a.createdAt > b.createdAt
            } }
        case .title:
            return tasks.sorted { compare($0, $1) { a, b in
                let r = a.title.localizedStandardCompare(b.title)
                return r == .orderedSame ? nil : r == .orderedAscending
            } }
        }
    }
}

/// 主键闭包返回 nil(无定论)时回退 boardOrder 升序决胜。
private func compare(_ a: TodoTask, _ b: TodoTask, _ key: (TodoTask, TodoTask) -> Bool?) -> Bool {
    if let r = key(a, b) { return r }
    return a.boardOrder < b.boardOrder
}
