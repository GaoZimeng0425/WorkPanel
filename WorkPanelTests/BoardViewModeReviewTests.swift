import Testing
@testable import WorkPanel

struct BoardViewModeReviewTests {
    @Test func reviewIsLastCaseWithLabel() {
        #expect(BoardViewMode.allCases.last == .review)
        #expect(BoardViewMode.review.label == "复盘")
    }
}
