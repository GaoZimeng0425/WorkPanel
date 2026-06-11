import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct AIContextTests {
    @Test func renderTaskIncludesTitleNotesTags() {
        let t = TodoTask(title: "写设计文档",
                         notes: "先列大纲\n再补细节",
                         priority: .high,
                         tags: ["工作", "文档"])
        let s = AIContext.renderTask(t)
        #expect(s.contains("写设计文档"))
        #expect(s.contains("先列大纲"))
        #expect(s.contains("工作"))
        #expect(s.contains("文档"))
    }

    @Test func renderInProgressListsOnlyIncompleteTasks() {
        let a = TodoTask(title: "任务A", priority: .high)
        let b = TodoTask(title: "任务B", priority: .low)
        let done = TodoTask(title: "已完成任务", priority: .medium)
        done.isCompleted = true
        let s = AIContext.renderInProgress([a, b, done])
        #expect(s.contains("任务A"))
        #expect(s.contains("任务B"))
        #expect(!s.contains("已完成任务"))
    }

    @Test func renderInProgressHandlesEmpty() {
        #expect(AIContext.renderInProgress([]) == "(当前没有进行中的任务)")
    }

    @Test func renderInProgressHandlesAllCompleted() {
        let done = TodoTask(title: "已完成任务", priority: .medium)
        done.isCompleted = true
        #expect(AIContext.renderInProgress([done]) == "(当前没有进行中的任务)")
    }
}
