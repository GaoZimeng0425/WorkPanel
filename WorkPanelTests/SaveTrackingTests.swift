import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct SaveTrackingTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    @Test func saveTrackingStampsInsertedModels() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "T")
        ctx.insert(task)
        task.modifiedAt = Date(timeIntervalSince1970: 0)
        let stamp = Date(timeIntervalSince1970: 1000)
        try ctx.saveTracking(now: stamp)
        #expect(task.modifiedAt == stamp)
    }

    @Test func saveTrackingStampsChangedModels() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "T")
        ctx.insert(task)
        task.modifiedAt = Date(timeIntervalSince1970: 0)
        try ctx.save()                       // 先落库,清空 inserted 集
        task.title = "改了"                   // 触发 changed
        let stamp = Date(timeIntervalSince1970: 2000)
        try ctx.saveTracking(now: stamp)
        #expect(task.modifiedAt == stamp)
    }

    @Test func plainSaveDoesNotStamp() throws {
        let ctx = try makeContext()
        let task = TodoTask(title: "T")
        ctx.insert(task)
        let early = Date(timeIntervalSince1970: 0)
        task.modifiedAt = early
        try ctx.save()
        #expect(task.modifiedAt == early)
    }
}
