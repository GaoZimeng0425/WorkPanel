import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct AISettingsTests {
    private func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: AppSettings.Key.aiBaseURL)
        d.removeObject(forKey: AppSettings.Key.aiModel)
        d.removeObject(forKey: AppSettings.Key.aiAPIKey)
    }

    @Test func aiConfigDefaultsToEmpty() {
        defer { clear() }
        clear()
        #expect(AppSettings.aiBaseURL.isEmpty)
        #expect(AppSettings.aiModel.isEmpty)
        #expect(AppSettings.aiAPIKey.isEmpty)
    }

    @Test func aiConfigPersistsSetValues() {
        defer { clear() }
        let d = UserDefaults.standard
        d.set("https://api.openai.com/v1", forKey: AppSettings.Key.aiBaseURL)
        d.set("gpt-4o-mini", forKey: AppSettings.Key.aiModel)
        d.set("sk-test", forKey: AppSettings.Key.aiAPIKey)
        #expect(AppSettings.aiBaseURL == "https://api.openai.com/v1")
        #expect(AppSettings.aiModel == "gpt-4o-mini")
        #expect(AppSettings.aiAPIKey == "sk-test")
    }
}
