import Testing
import AppKit
@testable import WorkPanel

/// 多个用例共享 defaults 键,必须串行避免互踩(同 JiraPullServiceTests)。
@Suite(.serialized)
@MainActor
struct AppSettingsTests {
    @Test func appearanceMapsToNSAppearance() {
        #expect(Appearance.system.nsAppearance == nil)
        #expect(Appearance.light.nsAppearance?.name == .aqua)
        #expect(Appearance.dark.nsAppearance?.name == .darkAqua)
    }

    @Test func appearanceHasLabelForEveryCase() {
        for a in Appearance.allCases {
            #expect(!a.label.isEmpty)
        }
    }

    @Test func mcpTokenGeneratesOnceAndPersists() {
        let defaults = AppSettings.defaults
        defaults.removeObject(forKey: AppSettings.Key.mcpToken)
        let first = AppSettings.mcpToken
        #expect(!first.isEmpty)
        #expect(AppSettings.mcpToken == first)   // stable across reads
        defaults.removeObject(forKey: AppSettings.Key.mcpToken)   // cleanup
    }

    @Test func mcpPortDefaultsTo8787() {
        defer { AppSettings.defaults.removeObject(forKey: AppSettings.Key.mcpPort) }
        AppSettings.defaults.removeObject(forKey: AppSettings.Key.mcpPort)
        #expect(AppSettings.mcpPort == 8787)
    }

    /// 越界值(UI 键入即落库,不依赖回车校验)必须回落默认,否则 UInt16() 启动即 trap。
    @Test func mcpPortOutOfRangeFallsBackTo8787() {
        for bad in [70000, -1, 65536] {
            AppSettings.defaults.set(bad, forKey: AppSettings.Key.mcpPort)
            #expect(AppSettings.mcpPort == 8787, "expected fallback for \(bad)")
        }
        AppSettings.defaults.set(9000, forKey: AppSettings.Key.mcpPort)
        #expect(AppSettings.mcpPort == 9000)
        AppSettings.defaults.removeObject(forKey: AppSettings.Key.mcpPort)
    }

    @Test func boardHeightDefaultsTo360() {
        defer { AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardHeight) }
        AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardHeight)
        #expect(AppSettings.boardHeight == 360)
    }

    @Test func boardHeightPersistsSetValue() {
        defer { AppSettings.defaults.removeObject(forKey: AppSettings.Key.boardHeight) }
        AppSettings.defaults.set(Double(640), forKey: AppSettings.Key.boardHeight)
        #expect(AppSettings.boardHeight == 640)
    }
}
