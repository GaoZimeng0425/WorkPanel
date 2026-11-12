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

    /// 各规则的常用方向(即 v1 现行为):优先级高在前、创建新在前;截止近在前、标题 A→Z。
    var preferredDescending: Bool {
        switch self {
        case .manual:    false   // 手动排序无方向概念
        case .priority:  true
        case .deadline:  false
        case .createdAt: true
        case .title:     false
        }
    }

    /// 按常用方向排序。
    func sorted(_ tasks: [TodoTask]) -> [TodoTask] {
        sorted(tasks, descending: preferredDescending)
    }

    /// 按规则与方向排序;升序为自然序(优先级低→高、截止近→远、创建旧→新、标题 A→Z)。
    /// 降序仅翻转主键结果:无截止任务殿后、平局 boardOrder 决胜,两个方向下行为不变,
    /// 且不依赖 sorted 的稳定性。
    func sorted(_ tasks: [TodoTask], descending: Bool) -> [TodoTask] {
        switch self {
        case .manual:
            return tasks.sorted { $0.boardOrder < $1.boardOrder }
        case .priority:
            return tasks.sorted { compare($0, $1) { a, b in
                naturalOrder(a.priorityRaw, b.priorityRaw, descending: descending)
            } }
        case .deadline:
            return tasks.sorted { compare($0, $1) { a, b in
                switch (a.deadline, b.deadline) {
                case let (x?, y?): return naturalOrder(x, y, descending: descending)
                case (nil, _?):    return false   // 无截止殿后,不随方向翻转
                case (_?, nil):    return true
                case (nil, nil):   return nil     // 交给 boardOrder 决胜
                }
            } }
        case .createdAt:
            return tasks.sorted { compare($0, $1) { a, b in
                naturalOrder(a.createdAt, b.createdAt, descending: descending)
            } }
        case .title:
            return tasks.sorted { compare($0, $1) { a, b in
                let r = a.title.localizedStandardCompare(b.title)
                if r == .orderedSame { return nil }
                return descending ? r == .orderedDescending : r == .orderedAscending
            } }
        }
    }
}

/// 主键闭包返回 nil(无定论)时回退 boardOrder 升序决胜。
private func compare(_ a: TodoTask, _ b: TodoTask, _ key: (TodoTask, TodoTask) -> Bool?) -> Bool {
    if let r = key(a, b) { return r }
    return a.boardOrder < b.boardOrder
}

/// 主键自然升序比较:相等返回 nil(交 boardOrder 决胜),降序翻转结果。
private func naturalOrder<T: Comparable>(_ x: T, _ y: T, descending: Bool) -> Bool? {
    x == y ? nil : (descending ? x > y : x < y)
}
