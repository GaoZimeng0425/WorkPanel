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
    }

    /// 在 App 启动时调用一次,确保未设置过的项使用正确默认值(尤其 notificationSound 默认 true)。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.reminderLeadMinutes: 0,
            Key.appearance: Appearance.system.rawValue,
            Key.notificationSound: true,
            Key.defaultPriority: Priority.medium.rawValue,
            Key.boardViewMode: BoardViewMode.kanban.rawValue,
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
