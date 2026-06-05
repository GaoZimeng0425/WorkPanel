import Foundation

/// 同步文件里的设置部分。白名单内的键全部 Optional —— 缺键即 nil,apply 时跳过。
/// 刻意不含 lastPlannedDay(本机当日规划状态,不应跨机器覆盖)。
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
}

enum SyncSettings {
    /// suiteName が nil のときはバンドル ID でフォールバックし、標準 UserDefaults の永続ドメインを読む。
    /// テストから独立スイートを渡すときは suiteName も明示すること。
    static func snapshot(from d: UserDefaults = .standard,
                         suiteName: String? = nil) -> SyncSettingsDTO {
        // 登録ドメイン(registerDefaults)のみのキーを除外するため、永続ドメインから読む。
        let domainName = suiteName ?? Bundle.main.bundleIdentifier ?? ""
        let persisted = d.persistentDomain(forName: domainName) ?? [:]

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
        return dto
    }

    static func apply(_ dto: SyncSettingsDTO, to d: UserDefaults = .standard) {
        let K = AppSettings.Key.self
        if let v = dto.reminderLeadMinutes { d.set(v, forKey: K.reminderLeadMinutes) }
        if let v = dto.appearance          { d.set(v, forKey: K.appearance) }
        if let v = dto.notificationSound   { d.set(v, forKey: K.notificationSound) }
        if let v = dto.defaultPriority     { d.set(v, forKey: K.defaultPriority) }
        if let v = dto.boardViewMode       { d.set(v, forKey: K.boardViewMode) }
        if let v = dto.mcpEnabled          { d.set(v, forKey: K.mcpEnabled) }
        if let v = dto.mcpPort             { d.set(v, forKey: K.mcpPort) }
        if let v = dto.mcpToken            { d.set(v, forKey: K.mcpToken) }
        if let v = dto.boardHeight         { d.set(v, forKey: K.boardHeight) }
        if let v = dto.aiBaseURL           { d.set(v, forKey: K.aiBaseURL) }
        if let v = dto.aiModel             { d.set(v, forKey: K.aiModel) }
        if let v = dto.aiAPIKey            { d.set(v, forKey: K.aiAPIKey) }
        if let v = dto.aiPrompts           { d.set(v, forKey: K.aiPrompts) }
    }
}
