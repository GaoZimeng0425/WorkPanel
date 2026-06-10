import Testing
@testable import WorkPanel

struct BoardViewModeReviewTests {
    @Test func reviewHasLabel() {
        #expect(BoardViewMode.review.label == "复盘")
    }

    @Test func allCasesIncludesGantt() {
        #expect(BoardViewMode.allCases.last == .gantt)
        #expect(BoardViewMode.gantt.label == "甘特")
        #expect(BoardViewMode(rawValue: "gantt") == .gantt)
    }
}
