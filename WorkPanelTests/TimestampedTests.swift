import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct TimestampedTests {
    @Test func threeModelsConformAndModifiedAtIsSettable() {
        let epoch = Date(timeIntervalSince1970: 0)
        let models: [any Timestamped] = [
            TodoTask(title: "a"),
            BoardColumn(name: "c", order: 0),
            DayPlan(day: .now),
        ]
        for m in models {
            m.modifiedAt = epoch
            #expect(m.modifiedAt == epoch)
        }
    }
}
