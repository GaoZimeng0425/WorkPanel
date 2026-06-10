import Testing
@testable import WorkPanel

struct BoardViewModeReviewTests {
    @Test func reviewHasLabel() {
        #expect(BoardViewMode.review.label == "复盘")
    }

    @Test func allCasesIncludesGantt() {
        // 顺序刻意固定:甘特在今日与优先级之间。
        #expect(BoardViewMode.allCases == [.kanban, .matrix, .today, .gantt, .priority, .review])
        #expect(BoardViewMode.gantt.label == "甘特")
        #expect(BoardViewMode(rawValue: "gantt") == .gantt)
    }
}
