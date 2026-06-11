import Testing
import Foundation
@testable import WorkPanel

struct ReorderTests {
    @Test func moveForwardInsertsBeforeTarget() {
        let a = UUID(), b = UUID(), c = UUID()
        // a 原索引 0 < 目标 2 → 移除后落到 index 1
        #expect(reorderInsertingBefore([a, b, c], move: a, before: 2) == [b, a, c])
    }

    @Test func moveBackwardInsertsBeforeTarget() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(reorderInsertingBefore([a, b, c], move: c, before: 0) == [c, a, b])
    }

    @Test func moveToContainerAppends() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(reorderInsertingBefore([a, b, c], move: a, before: 3) == [b, c, a])
    }

    @Test func unknownIDNoOp() {
        let a = UUID(), b = UUID()
        #expect(reorderInsertingBefore([a, b], move: UUID(), before: 0) == [a, b])
    }

    @Test func singleElementStable() {
        let a = UUID()
        #expect(reorderInsertingBefore([a], move: a, before: 0) == [a])
    }
}
