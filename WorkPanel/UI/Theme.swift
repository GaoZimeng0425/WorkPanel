import SwiftUI

/// 全 App 唯一的语义颜色、文案与尺寸来源。
/// 三处面板(列表 / 看板 / Capture)统一调用,避免重复实现导致的样式漂移。
enum Theme {
    // MARK: Noir 表面/描边/强调/文字 token
    nonisolated static let panelTop      = Color(red: 0.039, green: 0.035, blue: 0.031)
    nonisolated static let panelBottom   = Color(red: 0.005, green: 0.005, blue: 0.004)
    nonisolated static let surfaceSubtle   = Color.white.opacity(0.045)
    nonisolated static let surface         = Color.white.opacity(0.07)
    nonisolated static let surfaceEmphasis = Color.white.opacity(0.12)
    nonisolated static let surfaceWarm     = Color(red: 0.23, green: 0.11, blue: 0.035).opacity(0.64)
    nonisolated static let stroke       = Color.white.opacity(0.10)
    nonisolated static let strokeStrong = Color.white.opacity(0.15)
    nonisolated static let accent     = Color(red: 1.0, green: 0.55, blue: 0.08)
    nonisolated static let accentText = Color(red: 1.0, green: 0.58, blue: 0.28)
    nonisolated static let accentSoft = accent.opacity(0.18)
    nonisolated static let accentStroke = accent.opacity(0.42)
    nonisolated static let textPrimary   = Color.white.opacity(0.94)
    nonisolated static let textSecondary = Color.white.opacity(0.62)
    nonisolated static let textTertiary  = Color.white.opacity(0.42)
    nonisolated static let textMuted     = Color.white.opacity(0.30)

    // MARK: 语义色
    // nonisolated: 项目默认 MainActor 隔离,纯函数需显式 opt-out 以便测试在非隔离上下文调用
    nonisolated static func priority(_ p: Priority) -> Color {
        switch p {
        case .high:   Color(red: 1.0, green: 0.27, blue: 0.23) // #FF453A
        case .medium: Color(red: 1.0, green: 0.70, blue: 0.25) // #FFB340 琥珀,避让交互橙
        case .low:    textTertiary
        }
    }
    nonisolated static func quadrant(important: Bool, urgent: Bool) -> Color {
        switch (important, urgent) {
        case (true, true):   priority(.high)
        case (true, false):  Color(red: 0.30, green: 0.65, blue: 1.0) // #4DA6FF
        case (false, true):  priority(.medium)
        case (false, false): priority(.low)
        }
    }
    nonisolated static let tag        = Color(red: 0.36, green: 0.76, blue: 0.43) // #5BC16E
    nonisolated static let deadline   = Color(red: 0.30, green: 0.65, blue: 1.0)  // #4DA6FF
    nonisolated static let recurrence = Color(red: 0.73, green: 0.55, blue: 1.0)  // #B98BFF

    // MARK: 文案
    nonisolated static func priorityLabel(_ p: Priority) -> String {
        switch p { case .high: "高"; case .medium: "中"; case .low: "低" }
    }
    nonisolated static func recurrenceLabel(_ r: RecurrenceRule) -> String {
        switch r {
        case .daily:    "每天"
        case .weekdays: "工作日"
        case .weekly:   "每周"
        case .monthly:  "每月"
        }
    }

    // MARK: 尺寸 token (pt)
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 14
    static let columnRadius: CGFloat = 10
    static let titleFontSize: CGFloat = 13
    static let metaFontSize: CGFloat = 11
    static let priorityDotSize: CGFloat = 7
}
