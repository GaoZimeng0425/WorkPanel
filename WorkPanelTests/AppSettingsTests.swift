import Testing
import AppKit
@testable import WorkPanel

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
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppSettings.Key.mcpToken)
        let first = AppSettings.mcpToken
        #expect(!first.isEmpty)
        #expect(AppSettings.mcpToken == first)   // stable across reads
        defaults.removeObject(forKey: AppSettings.Key.mcpToken)   // cleanup
    }

    @Test func mcpPortDefaultsTo8787() {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.mcpPort) }
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.mcpPort)
        #expect(AppSettings.mcpPort == 8787)
    }

    @Test func boardHeightDefaultsTo360() {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.boardHeight) }
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.boardHeight)
        #expect(AppSettings.boardHeight == 360)
    }

    @Test func boardHeightPersistsSetValue() {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.boardHeight) }
        UserDefaults.standard.set(Double(640), forKey: AppSettings.Key.boardHeight)
        #expect(AppSettings.boardHeight == 640)
    }
}
