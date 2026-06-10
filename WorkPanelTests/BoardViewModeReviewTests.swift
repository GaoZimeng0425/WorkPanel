import Testing
@testable import WorkPanel

struct BoardViewModeReviewTests {
    @Test func reviewIsLastCaseWithLabel() {
        #expect(BoardViewMode.allCases.contains(.review))
        #expect(BoardViewMode.review.label == "复盘")
    }

    @Test func allCasesIncludesGantt() {
        #expect(BoardViewMode.allCases.contains(.gantt))
        #expect(BoardViewMode.gantt.label == "甘特")
        #expect(BoardViewMode(rawValue: "gantt") == .gantt)
    }
}
