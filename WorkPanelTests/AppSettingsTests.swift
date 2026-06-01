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
}
