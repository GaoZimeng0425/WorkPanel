import Foundation

/// 同步文件里的设置部分。白名单内的键全部 Optional —— 缺键即 nil,apply 时跳过。
/// 刻意不含 lastPlannedDay(本机当日规划状态,不应跨机器覆盖)与 jiraDismissedKeys(本机 dismiss 状态)。
struct SyncSettingsDTO: Codable {
    var reminderLeadMinutes: Int?
    var appearance: String?
    var notificationSound: Bool?
    var defaultPriority: Int?
    var boardViewMode: String?
    var mcpEnabled: Bool?
    var mcpPort: Int?
    var mcpToken: String?
    var boardHeight: Double?
    var aiBaseURL: String?
    var aiModel: String?
    var aiAPIKey: String?
    var aiPrompts: String?        // UserDefaults 里本就是 JSON 字符串,原样搬运
    var jiraDomain: String?
    var jiraEmail: String?
    var jiraAPIToken: String?
    var jiraJQL: String?
}

enum SyncSettings {
    /// 读取白名单设置。suiteName 为 nil 时以 Bundle ID 为后备域。
    /// 刻意从持久化域(persistentDomain)读取,以排除仅由 registerDefaults 注册、未被用户显式设置的键。
    static func snapshot(from defaults: UserDefaults = .standard,
                         suiteName: String? = nil) -> SyncSettingsDTO {
        let domainName = suiteName ?? Bundle.main.bundleIdentifier ?? ""
        let persisted = defaults.persistentDomain(forName: domainName) ?? [:]

        func obj(_ key: String) -> Any? { persisted[key] }

        var dto = SyncSettingsDTO()
        let K = AppSettings.Key.self
        dto.reminderLeadMinutes = obj(K.reminderLeadMinutes) as? Int
        dto.appearance          = obj(K.appearance) as? String
        dto.notificationSound   = obj(K.notificationSound) as? Bool
        dto.defaultPriority     = obj(K.defaultPriority) as? Int
        dto.boardViewMode       = obj(K.boardViewMode) as? String
        dto.mcpEnabled          = obj(K.mcpEnabled) as? Bool
        dto.mcpPort             = obj(K.mcpPort) as? Int
        dto.mcpToken            = obj(K.mcpToken) as? String
        dto.boardHeight         = obj(K.boardHeight) as? Double
        dto.aiBaseURL           = obj(K.aiBaseURL) as? String
        dto.aiModel             = obj(K.aiModel) as? String
        dto.aiAPIKey            = obj(K.aiAPIKey) as? String
        dto.aiPrompts           = obj(K.aiPrompts) as? String
        dto.jiraDomain          = obj(K.jiraDomain) as? String
        dto.jiraEmail           = obj(K.jiraEmail) as? String
        dto.jiraAPIToken        = obj(K.jiraAPIToken) as? String
        dto.jiraJQL             = obj(K.jiraJQL) as? String
        return dto
    }

    /// 按套件名读取(测试用):自动用同一套件名读取其持久化域,避免实例与域名不一致。
    static func snapshot(suiteName: String) -> SyncSettingsDTO {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return snapshot(from: defaults, suiteName: suiteName)
    }

    static func apply(_ dto: SyncSettingsDTO, to defaults: UserDefaults = .standard) {
        let K = AppSettings.Key.self
        if let v = dto.reminderLeadMinutes { defaults.set(v, forKey: K.reminderLeadMinutes) }
        if let v = dto.appearance          { defaults.set(v, forKey: K.appearance) }
        if let v = dto.notificationSound   { defaults.set(v, forKey: K.notificationSound) }
        if let v = dto.defaultPriority     { defaults.set(v, forKey: K.defaultPriority) }
        if let v = dto.boardViewMode       { defaults.set(v, forKey: K.boardViewMode) }
        if let v = dto.mcpEnabled          { defaults.set(v, forKey: K.mcpEnabled) }
        if let v = dto.mcpPort             { defaults.set(v, forKey: K.mcpPort) }
        if let v = dto.mcpToken            { defaults.set(v, forKey: K.mcpToken) }
        if let v = dto.boardHeight         { defaults.set(v, forKey: K.boardHeight) }
        if let v = dto.aiBaseURL           { defaults.set(v, forKey: K.aiBaseURL) }
        if let v = dto.aiModel             { defaults.set(v, forKey: K.aiModel) }
        if let v = dto.aiAPIKey            { defaults.set(v, forKey: K.aiAPIKey) }
        if let v = dto.aiPrompts           { defaults.set(v, forKey: K.aiPrompts) }
        if let v = dto.jiraDomain          { defaults.set(v, forKey: K.jiraDomain) }
        if let v = dto.jiraEmail           { defaults.set(v, forKey: K.jiraEmail) }
        if let v = dto.jiraAPIToken        { defaults.set(v, forKey: K.jiraAPIToken) }
        if let v = dto.jiraJQL             { defaults.set(v, forKey: K.jiraJQL) }
    }
}
