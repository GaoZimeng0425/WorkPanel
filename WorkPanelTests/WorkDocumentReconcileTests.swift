import Testing
import Foundation
@testable import WorkPanel

struct WorkDocumentReconcileTests {
    private let colA = UUID()

    private func liveSnap(_ id: UUID, _ title: String, priority: Priority = .medium,
                          tags: [String] = [], column: UUID? = nil, order: Int = 0) -> WorkTaskSnapshot {
        WorkTaskSnapshot(id: id, title: title, notes: "", priority: priority, tags: tags,
                         columnID: column, boardOrder: order)
    }

    @Test func updatesMatchedKeepsTimeFieldsImplicitly() {
        let id = UUID()
        let blocks = [WorkDocument.Block(columnID: colA, title: "写周报改", priority: nil, tags: [],
                                         notes: "新备注", completed: false, offset: 0)]
        let anchors = [WorkDocument.Anchor(id: id, offset: 0)]
        let live = [liveSnap(id, "写周报", priority: .high, tags: ["工作"], column: colA)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: anchors, liveTasks: live)
        #expect(cs.creates.isEmpty)
        #expect(cs.deletes.isEmpty)
        #expect(cs.updates == [.init(id: id, title: "写周报改", notes: "新备注",
                                     priority: .high, tags: ["工作"],    // 缺省保留
                                     columnID: colA, order: 0, complete: false)])
    }

    @Test func newBlockBecomesCreate() {
        let blocks = [WorkDocument.Block(columnID: colA, title: "新任务", priority: .low, tags: ["x"],
                                         notes: "", completed: false, offset: 0)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [], liveTasks: [])
        #expect(cs.updates.isEmpty)
        #expect(cs.creates == [.init(title: "新任务", notes: "", priority: .low, tags: ["x"],
                                     columnID: colA, order: 0)])
    }

    @Test func removedLineBecomesDelete() {
        let id = UUID()
        // 文档里没有这条任务的块(锚点已溶解)→ 删除
        let cs = WorkDocument.reconcile(blocks: [], anchors: [], liveTasks: [liveSnap(id, "买菜")])
        #expect(cs.deletes == [id])
    }

    @Test func externalTaskNotInSnapshotIsNeverDeleted() {
        // liveTasks 是打开时快照;外部新建的任务不在其中 → 不会出现在 deletes
        let cs = WorkDocument.reconcile(blocks: [], anchors: [], liveTasks: [])
        #expect(cs.deletes.isEmpty)
    }

    @Test func emptyTitleBlockSkipped() {
        let blocks = [WorkDocument.Block(columnID: colA, title: "   ", priority: nil, tags: [],
                                         notes: "", completed: false, offset: 0)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [], liveTasks: [])
        #expect(cs.creates.isEmpty && cs.updates.isEmpty && cs.deletes.isEmpty)
    }

    @Test func orderIsPerColumnDocumentOrder() {
        let blocks = [
            WorkDocument.Block(columnID: colA, title: "一", priority: nil, tags: [], notes: "", completed: false, offset: 0),
            WorkDocument.Block(columnID: nil,  title: "二", priority: nil, tags: [], notes: "", completed: false, offset: 10),
            WorkDocument.Block(columnID: colA, title: "三", priority: nil, tags: [], notes: "", completed: false, offset: 20),
        ]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [], liveTasks: [])
        let orders = Dictionary(uniqueKeysWithValues: cs.creates.map { ($0.title, ($0.columnID, $0.order)) })
        #expect(orders["一"]! == (colA, 0))
        #expect(orders["三"]! == (colA, 1))   // 同列内第二个
        #expect(orders["二"]! == (nil, 0))    // nil 列各自计数
    }

    @Test func checkedBoxMarksComplete() {
        let id = UUID()
        let blocks = [WorkDocument.Block(columnID: colA, title: "买菜", priority: nil, tags: [],
                                         notes: "", completed: true, offset: 0)]
        let cs = WorkDocument.reconcile(blocks: blocks, anchors: [.init(id: id, offset: 0)],
                                        liveTasks: [liveSnap(id, "买菜", column: colA)])
        #expect(cs.updates.first?.complete == true)
        #expect(cs.creates.isEmpty)
        #expect(cs.deletes.isEmpty)
    }

    @Test func anchorIdAbsentFromLiveBecomesCreate() {
        let staleID = UUID()
        let blocks = [WorkDocument.Block(columnID: colA, title: "孤儿", priority: nil, tags: [],
                                         notes: "", completed: false, offset: 0)]
        // 锚点偏移命中,但该 id 不在 liveTasks 快照里 → 应当新建,而非更新/删除
        let cs = WorkDocument.reconcile(blocks: blocks,
                                        anchors: [.init(id: staleID, offset: 0)],
                                        liveTasks: [])
        #expect(cs.updates.isEmpty)
        #expect(cs.deletes.isEmpty)
        #expect(cs.creates.map(\.title) == ["孤儿"])
    }
}
