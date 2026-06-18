import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentParseTests {
    private let colA = UUID()
    private func columns() -> [WorkColumn] { [WorkColumn(id: colA, name: "计划中")] }

    @Test func parsesItemsHeadingsNotes() {
        let text = """
        ## 计划中
        - [ ] 写周报 !高 #工作
            汇总进展
            第二行备注
        - [x] 买菜
        """
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(blocks.count == 2)
        #expect(blocks[0].columnID == colA)
        #expect(blocks[0].title == "写周报")
        #expect(blocks[0].priority == .high)
        #expect(blocks[0].tags == ["工作"])
        #expect(blocks[0].notes == "汇总进展\n第二行备注")
        #expect(blocks[0].completed == false)
        #expect(blocks[1].title == "买菜")
        #expect(blocks[1].completed == true)
        #expect(blocks[1].notes == "")
    }

    @Test func unknownHeadingMapsToNilColumn() {
        let text = "## 未分类\n- [ ] 随手记"
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(blocks[0].columnID == nil)
    }

    @Test func offsetPointsAtDash() {
        let text = "## 计划中\n- [ ] 写周报"
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(Array(text)[blocks[0].offset] == "-")
    }

    @Test func roundTripsThroughSerialize() {
        let id = UUID()
        let snap = WorkTaskSnapshot(id: id, title: "写周报", notes: "备注一行",
                                    priority: .high, tags: ["工作"], columnID: colA, boardOrder: 0)
        let (text, anchors) = WorkDocument.serialize(columns: columns(), tasks: [snap])
        let blocks = WorkDocument.parse(text: text, columns: columns())
        #expect(blocks.count == 1)
        #expect(blocks[0].offset == anchors[0].offset)   // 锚点 ↔ 块偏移对齐
        #expect(blocks[0].title == "写周报")
        #expect(blocks[0].notes == "备注一行")
    }
}
