import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentShiftTests {
    private func edit(_ old: String, _ new: String) -> WorkDocument.Edit {
        WorkDocument.computeEdit(old: Array(old), new: Array(new))
    }

    @Test func computeEditFindsSingleSpan() {
        #expect(edit("abcdef", "abXcdef") == .init(loc: 2, oldLen: 0, newLen: 1))   // 在 2 处插入 X
        #expect(edit("abcdef", "abdef") == .init(loc: 2, oldLen: 1, newLen: 0))      // 删 c
        #expect(edit("abc", "abc") == .init(loc: 3, oldLen: 0, newLen: 0))           // 无变化
    }

    @Test func anchorAfterEditShifts() {
        let e = WorkDocument.Edit(loc: 0, oldLen: 0, newLen: 3)   // 在最前插入 3 字
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 10)], by: e)
        #expect(out == [.init(id: idA, offset: 13)])
    }

    @Test func anchorBeforeEditUnchanged() {
        let e = WorkDocument.Edit(loc: 20, oldLen: 2, newLen: 5)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 10)], by: e)
        #expect(out == [.init(id: idA, offset: 10)])
    }

    @Test func editInsideTitleKeepsAnchor() {
        // 锚点在行首 offset=5,在标题中部(offset 9)改字 → 锚点不动
        let e = WorkDocument.Edit(loc: 9, oldLen: 1, newLen: 4)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 5)], by: e)
        #expect(out == [.init(id: idA, offset: 5)])
    }

    @Test func fullLineDeletionDissolvesAnchor() {
        // 删除区间 [5, 15) 覆盖行首锚点 offset=5 → 溶解
        let e = WorkDocument.Edit(loc: 5, oldLen: 10, newLen: 0)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 5)], by: e)
        #expect(out.isEmpty)
    }

    @Test func insertionAtAnchorPushesAnchorRight() {
        // 在行首正前方插入(loc==offset)→ '-' 右移,锚点跟着右移
        let e = WorkDocument.Edit(loc: 5, oldLen: 0, newLen: 2)
        let out = WorkDocument.shift(anchors: [.init(id: idA, offset: 5)], by: e)
        #expect(out == [.init(id: idA, offset: 7)])
    }

    private let idA = UUID()
}
