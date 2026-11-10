import AppKit

/// 全 App 的偏好持久化层。键集中定义,SwiftUI 控件用 @AppStorage 绑定相同键,
/// 非视图消费方读取这里的类型化访问器。
///
/// `defaults`:测试宿主就是本 App,若直用 .standard,单测对映射/忽略表的读写会
/// 污染真实配置(实测发生过:测试 defer 清键把用户映射删光)。测试进程改用隔离套件。
enum AppSettings {
    static let defaults: UserDefaults = {
        let env = ProcessInfo.processInfo.environment
        let inTests = env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["WORKPANEL_TEST_DEFAULTS"] == "1"
        guard inTests else { return .standard }
        let suite = UserDefaults(suiteName: "WorkPanelTests") ?? .standard
        suite.removePersistentDomain(forName: "WorkPanelTests")
        return suite
    }()

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
        static let jiraDomain = "jiraDomain"
        static let jiraEmail = "jiraEmail"
        static let jiraAPIToken = "jiraAPIToken"   // 明文,与 aiAPIKey 一致
        static let jiraJQL = "jiraJQL"
        static let jiraDismissedKeys = "jiraDismissedKeys"
        static let jiraColumnMapping = "jiraColumnMapping"       // JSON: [项目:[状态:列名]]
        static let jiraDiscoveredStatuses = "jiraDiscoveredStatuses" // JSON: [JiraDiscoveredStatus]
        static let jiraAutoPullMinutes = "jiraAutoPullMinutes"       // 0 = 关闭   // [String],本机 dismiss 状态,不导出
    }

    /// 在 App 启动时调用一次,确保未设置过的项使用正确默认值(尤其 notificationSound 默认 true)。
    static func registerDefaults() {
        defaults.register(defaults: [
            Key.reminderLeadMinutes: 0,
            Key.appearance: Appearance.system.rawValue,
            Key.notificationSound: true,
            Key.defaultPriority: Priority.medium.rawValue,
            Key.boardViewMode: BoardViewMode.kanban.rawValue,
            Key.mcpEnabled: false,
            Key.mcpPort: 8787,
            Key.jiraAutoPullMinutes: 0,
            Key.jiraDomain: "antalpha.atlassian.net",
            Key.jiraJQL: defaultJQL,
        ])
    }

    static var reminderLeadMinutes: Int {
        defaults.integer(forKey: Key.reminderLeadMinutes)
    }
    static var notificationSound: Bool {
        defaults.bool(forKey: Key.notificationSound)
    }
    static var defaultPriority: Priority {
        Priority(rawValue: defaults.integer(forKey: Key.defaultPriority)) ?? .medium
    }
    static var appearance: Appearance {
        Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
    }
    static var mcpEnabled: Bool {
        defaults.bool(forKey: Key.mcpEnabled)
    }
    static var mcpPort: Int {
        let p = defaults.integer(forKey: Key.mcpPort)
        return p == 0 ? 8787 : p
    }
    static var mcpToken: String {
        if let t = defaults.string(forKey: Key.mcpToken), !t.isEmpty { return t }
        let t = UUID().uuidString
        defaults.set(t, forKey: Key.mcpToken)
        return t
    }
    static var boardHeight: CGFloat {
        let h = defaults.double(forKey: Key.boardHeight)
        return h == 0 ? 360 : CGFloat(h)
    }
    static var aiBaseURL: String {
        defaults.string(forKey: Key.aiBaseURL) ?? ""
    }
    static var aiModel: String {
        defaults.string(forKey: Key.aiModel) ?? ""
    }
    static var aiAPIKey: String {
        defaults.string(forKey: Key.aiAPIKey) ?? ""
    }
    /// 三项配置齐全才算可用——AI 入口的显示门槛,与 AIRequest.build 的校验一致。
    static var aiConfigured: Bool {
        !aiBaseURL.isEmpty && !aiModel.isEmpty && !aiAPIKey.isEmpty
    }
    /// 默认 JQL:当前用户的未完成事项,按更新时间倒序。
    static let defaultJQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
    static var jiraDomain: String {
        let s = defaults.string(forKey: Key.jiraDomain) ?? ""
        return s.isEmpty ? "antalpha.atlassian.net" : s
    }
    static var jiraEmail: String {
        defaults.string(forKey: Key.jiraEmail) ?? ""
    }
    static var jiraAPIToken: String {
        defaults.string(forKey: Key.jiraAPIToken) ?? ""
    }
    static var jiraJQL: String {
        let s = defaults.string(forKey: Key.jiraJQL) ?? ""
        return s.isEmpty ? defaultJQL : s
    }
    /// 三项配置齐全才算可用——Jira 入口的显示门槛。
    /// 自动拉取间隔(分钟);0 = 关闭。
    static var jiraAutoPullMinutes: Int {
        let m = defaults.integer(forKey: Key.jiraAutoPullMinutes)
        return max(0, m)
    }
    static var jiraConfigured: Bool {
        !jiraDomain.isEmpty && !jiraEmail.isEmpty && !jiraAPIToken.isEmpty
    }
    /// 本机已 dismiss 的 Jira 任务键(denylist,不随导出走)。
    static var jiraDismissedKeys: [String] {
        defaults.stringArray(forKey: Key.jiraDismissedKeys) ?? []
    }
    static func jiraDismiss(_ key: String) {
        var keys = jiraDismissedKeys
        if !keys.contains(key) { keys.append(key) }
        defaults.set(keys, forKey: Key.jiraDismissedKeys)
    }
    static func jiraResetDismissed() {
        defaults.removeObject(forKey: Key.jiraDismissedKeys)
    }
}

/// 拉取时发现过的 (项目, 状态) 对,供设置面板渲染映射行。
struct JiraDiscoveredStatus: Codable, Hashable, Sendable {
    var project: String
    var status: String
}

extension AppSettings {
    /// 项目 → (状态名 → 看板列名)。每机配置,不进导出白名单。
    static var jiraColumnMapping: [String: [String: String]] {
        get {
            guard let raw = defaults.string(forKey: Key.jiraColumnMapping),
                  let dict = try? JSONDecoder().decode([String: [String: String]].self,
                                                       from: Data(raw.utf8)) else { return [:] }
            return dict
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else { return }
            defaults.set(raw, forKey: Key.jiraColumnMapping)
        }
    }

    /// 最近一次拉取见过的 (项目, 状态),整体替换。
    static var jiraDiscoveredStatuses: [JiraDiscoveredStatus] {
        get {
            guard let raw = defaults.string(forKey: Key.jiraDiscoveredStatuses),
                  let list = try? JSONDecoder().decode([JiraDiscoveredStatus].self,
                                                       from: Data(raw.utf8)) else { return [] }
            return list
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else { return }
            defaults.set(raw, forKey: Key.jiraDiscoveredStatuses)
        }
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
