import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct SyncServiceMergeTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    private func docWith(tasks: [SyncTaskDTO] = [], columns: [SyncColumnDTO] = [],
                         dayPlans: [SyncDayPlanDTO] = [],
                         settings: SyncSettingsDTO = SyncSettingsDTO()) -> SyncDocument {
        SyncDocument(schemaVersion: 1, exportedAt: .now,
                     tasks: tasks, columns: columns, dayPlans: dayPlans, settings: settings)
    }

    @Test func insertsTaskNotPresentLocally() throws {
        let ctx = try makeContext()
        let incoming = TodoTask(title: "新")
        incoming.modifiedAt = Date(timeIntervalSince1970: 10)
        let report = try SyncService.merge(docWith(tasks: [SyncTaskDTO(incoming)]),
                                       into: ctx, includeSettings: false)
        let all = try ctx.fetch(FetchDescriptor<TodoTask>())
        #expect(all.count == 1)
        #expect(all.first?.title == "新")
        #expect(report.tasksInserted == 1)
        #expect(report.tasksUpdated == 0)
    }

    @Test func newerIncomingOverwritesLocal() throws {
        let ctx = try makeContext()
        let local = TodoTask(title: "旧标题")
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local)
        try ctx.save()

        var dto = SyncTaskDTO(local)
        dto.title = "新标题"
        dto.modifiedAt = Date(timeIntervalSince1970: 20)   // 更新

        let report = try SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(local.title == "新标题")
        #expect(report.tasksUpdated == 1)
        #expect(report.tasksInserted == 0)
    }

    @Test func olderIncomingIsSkipped() throws {
        let ctx = try makeContext()
        let local = TodoTask(title: "本地新")
        local.modifiedAt = Date(timeIntervalSince1970: 30)
        ctx.insert(local)
        try ctx.save()

        var dto = SyncTaskDTO(local)
        dto.title = "文件旧"
        dto.modifiedAt = Date(timeIntervalSince1970: 5)    // 更旧

        let report = try SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(local.title == "本地新")
        #expect(report.tasksUpdated == 0)
    }

    @Test func equalTimestampIsSkipped() throws {
        let ctx = try makeContext()
        let local = TodoTask(title: "本地")
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local)
        try ctx.save()

        var dto = SyncTaskDTO(local)
        dto.title = "文件"
        dto.modifiedAt = Date(timeIntervalSince1970: 10)   // 相等
        let report = try SyncService.merge(docWith(tasks: [dto]), into: ctx, includeSettings: false)
        #expect(local.title == "本地")
        #expect(report.tasksUpdated == 0)
    }

    @Test func dayPlanMatchedByDayNotInstant() throws {
        let ctx = try makeContext()
        let cal = Calendar(identifier: .gregorian)
        let morning = cal.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let local = DayPlan(day: morning, committedTaskIDs: [])
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local)
        try ctx.save()

        let evening = morning.addingTimeInterval(20 * 3600)   // 同一天稍晚
        let newID = UUID()
        var dto = SyncDayPlanDTO(DayPlan(day: evening, committedTaskIDs: [newID]))
        dto.modifiedAt = Date(timeIntervalSince1970: 20)

        let report = try SyncService.merge(docWith(dayPlans: [dto]),
                                       into: ctx, includeSettings: false, calendar: cal)
        let all = try ctx.fetch(FetchDescriptor<DayPlan>())
        #expect(all.count == 1)                       // 没有新建,合到同一天
        #expect(all.first?.committedTaskIDs == [newID])
        #expect(report.dayPlansUpdated == 1)
    }

    @Test func settingsAppliedOnlyWhenRequested() throws {
        let ctx = try makeContext()
        var settings = SyncSettingsDTO()
        settings.aiModel = "gpt-x"
        // includeSettings: false → 不应用
        let r1 = try SyncService.merge(docWith(settings: settings), into: ctx, includeSettings: false)
        #expect(r1.settingsApplied == false)
        // includeSettings: true → settingsApplied 为真
        let r2 = try SyncService.merge(docWith(settings: settings), into: ctx, includeSettings: true)
        #expect(r2.settingsApplied == true)
    }

    @Test func insertsColumnNotPresentLocally() throws {
        let ctx = try makeContext()
        let incoming = BoardColumn(name: "新列", order: 3)
        incoming.modifiedAt = Date(timeIntervalSince1970: 10)
        let report = try SyncService.merge(docWith(columns: [SyncColumnDTO(incoming)]),
                                           into: ctx, includeSettings: false)
        let all = try ctx.fetch(FetchDescriptor<BoardColumn>())
        #expect(all.count == 1)
        #expect(all.first?.name == "新列")
        #expect(report.columnsInserted == 1)
    }

    @Test func newerIncomingColumnOverwritesLocal() throws {
        let ctx = try makeContext()
        let local = BoardColumn(name: "旧名", order: 0)
        local.modifiedAt = Date(timeIntervalSince1970: 10)
        ctx.insert(local)
        try ctx.save()
        var dto = SyncColumnDTO(local)
        dto.name = "新名"
        dto.modifiedAt = Date(timeIntervalSince1970: 20)
        let report = try SyncService.merge(docWith(columns: [dto]), into: ctx, includeSettings: false)
        #expect(local.name == "新名")
        #expect(report.columnsUpdated == 1)
    }
}
