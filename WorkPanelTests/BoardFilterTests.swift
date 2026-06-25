import Foundation
import Testing
@testable import WorkPanel

@MainActor
struct BoardFilterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample() -> [TodoTask] {
        [
            TodoTask(title: "写周报", notes: "本周总结", deadline: now.addingTimeInterval(3600),
                     priority: .high, tags: ["工作"]),
            TodoTask(title: "买菜", notes: "西红柿鸡蛋", priority: .low, tags: ["生活"]),
            TodoTask(title: "读论文", notes: "", priority: .medium, tags: ["工作", "学习"]),
        ]
    }

    @Test func emptyFilterReturnsAllAndIsInactive() {
        let f = BoardFilter()
        #expect(f.isActive == false)
        #expect(f.apply(sample(), asOf: now).count == 3)
    }

    @Test func searchMatchesTitleOrNotesCaseInsensitively() {
        let f = BoardFilter()
        f.searchText = "周报"
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报"])
        f.searchText = "西红柿"          // notes hit
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["买菜"])
        f.searchText = "  "             // whitespace-only → inactive
        #expect(f.isActive == false)
        #expect(f.apply(sample(), asOf: now).count == 3)
    }

    @Test func tagsMatchAnySelected() {
        let f = BoardFilter()
        f.tags = ["工作"]
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报", "读论文"])
        f.tags = ["生活", "学习"]        // OR across selected tags
        #expect(Set(f.apply(sample(), asOf: now).map(\.title)) == ["买菜", "读论文"])
    }

    @Test func prioritiesMatchSelectedSet() {
        let f = BoardFilter()
        f.priorities = [.high, .low]
        #expect(Set(f.apply(sample(), asOf: now).map(\.title)) == ["写周报", "买菜"])
    }

    @Test func urgentOnlyKeepsUrgent() {
        let f = BoardFilter()
        f.urgentOnly = true
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报"])
    }

    @Test func dimensionsCombineWithAnd() {
        let f = BoardFilter()
        f.tags = ["工作"]
        f.priorities = [.high]
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报"])
    }

    @Test func clearResetsEverything() {
        let f = BoardFilter()
        f.searchText = "x"; f.tags = ["工作"]; f.priorities = [.high]; f.urgentOnly = true
        f.clear()
        #expect(f.isActive == false)
        #expect(f.searchText.isEmpty)
        #expect(f.tags.isEmpty)
        #expect(f.priorities.isEmpty)
        #expect(f.urgentOnly == false)
    }
}
