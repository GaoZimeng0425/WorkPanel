import AppKit

/// 全 App 的偏好持久化层。键集中定义,SwiftUI 控件用 @AppStorage 绑定相同键,
/// 非视图消费方读取这里的类型化访问器。
enum AppSettings {
    enum Key {
        static let reminderLeadMinutes = "reminderLeadMinutes"
        static let appearance = "appearance"
        static let notificationSound = "notificationSound"
        static let defaultPriority = "defaultPriority"
        static let boardViewMode = "boardViewMode"
        static let lastPlannedDay = "lastPlannedDay"   // Double: 上次开工规划日的 timeIntervalSinceReferenceDate
        static let mcpEnabled = "mcpEnabled"
        static let mcpPort = "mcpPort"
        static let mcpToken = "mcpToken"
        static let boardHeight = "boardHeight"   // Double: 看板像素高度,360 为最小/默认
        static let aiBaseURL = "aiBaseURL"
        static let aiModel = "aiModel"
        static let aiAPIKey = "aiAPIKey"   // 明文,与 mcpToken 一致
        static let aiPrompts = "aiPrompts" // JSON 编码的 [AIPrompt]
    }

    /// 在 App 启动时调用一次,确保未设置过的项使用正确默认值(尤其 notificationSound 默认 true)。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.reminderLeadMinutes: 0,
            Key.appearance: Appearance.system.rawValue,
            Key.notificationSound: true,
            Key.defaultPriority: Priority.medium.rawValue,
            Key.boardViewMode: BoardViewMode.kanban.rawValue,
            Key.mcpEnabled: false,
            Key.mcpPort: 8787,
        ])
    }

    static var reminderLeadMinutes: Int {
        UserDefaults.standard.integer(forKey: Key.reminderLeadMinutes)
    }
    static var notificationSound: Bool {
        UserDefaults.standard.bool(forKey: Key.notificationSound)
    }
    static var defaultPriority: Priority {
        Priority(rawValue: UserDefaults.standard.integer(forKey: Key.defaultPriority)) ?? .medium
    }
    static var appearance: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: Key.appearance) ?? "") ?? .system
    }
    static var mcpEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.mcpEnabled)
    }
    static var mcpPort: Int {
        let p = UserDefaults.standard.integer(forKey: Key.mcpPort)
        return p == 0 ? 8787 : p
    }
    static var mcpToken: String {
        if let t = UserDefaults.standard.string(forKey: Key.mcpToken), !t.isEmpty { return t }
        let t = UUID().uuidString
        UserDefaults.standard.set(t, forKey: Key.mcpToken)
        return t
    }
    static var boardHeight: CGFloat {
        let h = UserDefaults.standard.double(forKey: Key.boardHeight)
        return h == 0 ? 360 : CGFloat(h)
    }
    static var aiBaseURL: String {
        UserDefaults.standard.string(forKey: Key.aiBaseURL) ?? ""
    }
    static var aiModel: String {
        UserDefaults.standard.string(forKey: Key.aiModel) ?? ""
    }
    static var aiAPIKey: String {
        UserDefaults.standard.string(forKey: Key.aiAPIKey) ?? ""
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light:  "浅色"
        case .dark:   "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    /// 应用到整个 App(所有 AppKit 浮窗与其内嵌 SwiftUI 内容均跟随)。
    @MainActor func apply() {
        NSApp.appearance = nsAppearance
    }
}
