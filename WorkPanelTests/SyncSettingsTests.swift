import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncSettingsTests {
    /// 用独立 suiteName 的 UserDefaults,避免污染真实偏好。
    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "SyncSettingsTests")!
        for k in d.dictionaryRepresentation().keys { d.removeObject(forKey: k) }
        return d
    }

    @Test func snapshotReadsWhitelistedKeys() {
        let d = makeDefaults()
        d.set(15, forKey: AppSettings.Key.reminderLeadMinutes)
        d.set("dark", forKey: AppSettings.Key.appearance)
        d.set("sk-secret", forKey: AppSettings.Key.aiAPIKey)
        let dto = SyncSettings.snapshot(suiteName: "SyncSettingsTests")
        #expect(dto.reminderLeadMinutes == 15)
        #expect(dto.appearance == "dark")
        #expect(dto.aiAPIKey == "sk-secret")
        #expect(dto.mcpPort == nil)          // 未设置 → nil
    }

    @Test func applyWritesOnlyNonNilKeys() {
        let d = makeDefaults()
        d.set(99, forKey: AppSettings.Key.mcpPort)
        var dto = SyncSettingsDTO()
        dto.appearance = "light"             // 仅这一项有值
        SyncSettings.apply(dto, to: d)
        #expect(d.string(forKey: AppSettings.Key.appearance) == "light")
        #expect(d.integer(forKey: AppSettings.Key.mcpPort) == 99)   // 未被 nil 覆盖
    }

    @Test func excludesLastPlannedDay() {
        let d = makeDefaults()
        d.set(123.0, forKey: AppSettings.Key.lastPlannedDay)
        let dto = SyncSettings.snapshot(suiteName: "SyncSettingsTests")
        // DTO 无该字段;apply 也不会触碰它
        var fresh = SyncSettingsDTO()
        fresh.mcpPort = 1
        SyncSettings.apply(fresh, to: d)
        #expect(d.double(forKey: AppSettings.Key.lastPlannedDay) == 123.0)
    }
}
