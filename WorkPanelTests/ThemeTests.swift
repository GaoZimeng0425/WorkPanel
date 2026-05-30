import Testing
import SwiftUI
@testable import WorkPanel

struct ThemeTests {
    @Test func priorityLabels() {
        #expect(Theme.priorityLabel(.high) == "高")
        #expect(Theme.priorityLabel(.medium) == "中")
        #expect(Theme.priorityLabel(.low) == "低")
    }

    @Test func recurrenceLabels() {
        #expect(Theme.recurrenceLabel(.daily) == "每天")
        #expect(Theme.recurrenceLabel(.weekdays) == "工作日")
        #expect(Theme.recurrenceLabel(.weekly) == "每周")
        #expect(Theme.recurrenceLabel(.monthly) == "每月")
    }

    @Test func priorityColors() {
        #expect(Theme.priority(.high) == .red)
        #expect(Theme.priority(.medium) == .orange)
        #expect(Theme.priority(.low) == .gray)
    }
}
