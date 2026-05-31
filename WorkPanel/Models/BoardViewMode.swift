import Foundation

/// 看板顶部 tab 的透镜模式。rawValue 用于 @AppStorage 持久化。
enum BoardViewMode: String, CaseIterable, Identifiable {
    case kanban, matrix, today, priority

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kanban:   "看板"
        case .matrix:   "象限"
        case .today:    "今日"
        case .priority: "优先级"
        }
    }
}
