import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct AIPromptTests {
    private func clear() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.aiPrompts)
    }

    @Test func loadReturnsBuiltInDefaultsWhenEmpty() {
        defer { clear() }
        clear()
        let prompts = AIPromptStore.load()
        #expect(prompts.count == 2)
        #expect(prompts.contains { $0.shape == .singleTask })
        #expect(prompts.contains { $0.shape == .review })
    }

    @Test func saveThenLoadRoundTrips() {
        defer { clear() }
        let custom = [
            AIPrompt(id: UUID(), name: "我的拓展", shape: .singleTask, template: "AAA"),
            AIPrompt(id: UUID(), name: "我的复盘", shape: .review, template: "BBB"),
            AIPrompt(id: UUID(), name: "另一个", shape: .singleTask, template: "CCC"),
        ]
        AIPromptStore.save(custom)
        let loaded = AIPromptStore.load()
        #expect(loaded.count == 3)
        #expect(loaded[0].name == "我的拓展")
        #expect(loaded[2].template == "CCC")
        #expect(loaded[1].shape == .review)
    }

    @Test func defaultsHaveStableIDsAcrossLoads() {
        defer { clear() }
        clear()
        let a = AIPromptStore.load()
        let b = AIPromptStore.load()
        #expect(a.map(\.id) == b.map(\.id))
    }
}
