import SwiftUI

/// 全 App 唯一的语义颜色、文案与尺寸来源。
/// 三处面板(列表 / 看板 / Capture)统一调用,避免重复实现导致的样式漂移。
enum Theme {
    // MARK: 语义色
    nonisolated static func priority(_ p: Priority) -> Color {
        switch p { case .high: .red; case .medium: .orange; case .low: .gray }
    }
    static let tag: Color = .green
    static let deadline: Color = .blue
    static let recurrence: Color = .purple

    // MARK: 文案
    nonisolated static func priorityLabel(_ p: Priority) -> String {
        switch p { case .high: "高"; case .medium: "中"; case .low: "低" }
    }
    nonisolated static func recurrenceLabel(_ r: RecurrenceRule) -> String {
        switch r { case .daily: "每天"; case .weekdays: "工作日"; case .weekly: "每周"; case .monthly: "每月" }
    }

    // MARK: 尺寸 token
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 14
    static let titleFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let priorityDotSize: CGFloat = 7
}
