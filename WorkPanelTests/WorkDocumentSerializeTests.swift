import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentSerializeTests {
    private let colA = UUID(), colB = UUID()
    private func columns() -> [WorkColumn] {
        [WorkColumn(id: colA, name: "计划中"), WorkColumn(id: colB, name: "开发中")]
    }

    @Test func groupsByColumnInOrderWithTokensAndNotes() {
        let t1 = WorkTaskSnapshot(id: UUID(), title: "写周报", notes: "汇总本周进展\n@张三",
                                  priority: .high, tags: ["工作"], columnID: colA, boardOrder: 0)
        let t2 = WorkTaskSnapshot(id: UUID(), title: "买菜", notes: "",
                                  priority: .medium, tags: [], columnID: colA, boardOrder: 1)
        let t3 = WorkTaskSnapshot(id: UUID(), title: "修复bug", notes: "",
                                  priority: .low, tags: [], columnID: colB, boardOrder: 0)
        let r = WorkDocument.serialize(columns: columns(), tasks: [t1, t2, t3])
        #expect(r.text == """
        ## 计划中
        - [ ] 写周报 !高 #工作
            汇总本周进展
            @张三
        - [ ] 买菜

        ## 开发中
        - [ ] 修复bug !低
        """)
    }

    @Test func uncategorizedHeadingOnlyWhenNilColumnTasksExist() {
        let none = WorkTaskSnapshot(id: UUID(), title: "随手记", notes: "",
                                    priority: .medium, tags: [], columnID: nil, boardOrder: 0)
        let r = WorkDocument.serialize(columns: columns(), tasks: [none])
        #expect(r.text.contains("## 未分类"))
        #expect(r.text.contains("- [ ] 随手记"))

        let empty = WorkDocument.serialize(columns: columns(), tasks: [])
        #expect(!empty.text.contains("## 未分类"))
    }

    @Test func anchorOffsetsPointAtItemDash() {
        let id1 = UUID()
        let t1 = WorkTaskSnapshot(id: id1, title: "写周报", notes: "",
                                  priority: .medium, tags: [], columnID: colA, boardOrder: 0)
        let r = WorkDocument.serialize(columns: columns(), tasks: [t1])
        let chars = Array(r.text)
        let anchor = r.anchors.first { $0.id == id1 }!
        #expect(chars[anchor.offset] == "-")            // 锚点落在条目行的 '-'
    }
}
