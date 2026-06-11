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
        #expect(Theme.priority(.high)   == Color(red: 1.0, green: 0.27, blue: 0.23))
        #expect(Theme.priority(.medium) == Color(red: 1.0, green: 0.70, blue: 0.25))
        #expect(Theme.priority(.low)    == Color.white.opacity(0.42))
    }

    @Test func columnColorWrapsByModulo() {
        let n = Theme.columnPalette.count
        #expect(n >= 4)
        #expect(Theme.columnColor(order: 0) == Theme.columnPalette[0])
        #expect(Theme.columnColor(order: n) == Theme.columnPalette[0])       // 取模回绕
        #expect(Theme.columnColor(order: n + 1) == Theme.columnPalette[1])
        #expect(Theme.columnColor(order: -1) == Theme.columnPalette[n - 1])  // 负数也安全
    }
}
