import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct SyncServiceExportTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    @Test func exportThenParseReproducesCounts() throws {
        let ctx = try makeContext()
        ctx.insert(BoardColumn(name: "计划中", order: 0))
        ctx.insert(TodoTask(title: "A"))
        ctx.insert(TodoTask(title: "B"))
        ctx.insert(DayPlan(day: Date(timeIntervalSince1970: 0)))
        try ctx.save()

        let data = try SyncService.exportData(context: ctx, now: Date(timeIntervalSince1970: 999))
        let doc = try SyncService.parse(data)

        #expect(doc.schemaVersion == SyncDocument.currentSchemaVersion)
        #expect(doc.exportedAt == Date(timeIntervalSince1970: 999))
        #expect(doc.columns.count == 1)
        #expect(doc.tasks.count == 2)
        #expect(doc.dayPlans.count == 1)
    }

    @Test func parseRejectsUnknownSchemaVersion() throws {
        let json = #"{"schemaVersion":999,"exportedAt":"2026-01-01T00:00:00Z","tasks":[],"columns":[],"dayPlans":[],"settings":{}}"#
        #expect(throws: SyncError.unsupportedVersion(999)) {
            try SyncService.parse(Data(json.utf8))
        }
    }

    @Test func parseRejectsCorruptData() {
        #expect(throws: (any Error).self) {
            try SyncService.parse(Data("not json".utf8))
        }
    }

    @Test func exportWithoutSettingsOmitsSecrets() throws {
        let ctx = try makeContext()
        ctx.insert(TodoTask(title: "A"))
        try ctx.save()
        let data = try SyncService.exportData(context: ctx, includeSettings: false)
        let doc = try SyncService.parse(data)
        // includeSettings:false → settings 全部字段为 nil(不读取任何偏好,线上无密钥)
        #expect(doc.settings.aiAPIKey == nil)
        #expect(doc.settings.mcpToken == nil)
        #expect(doc.settings.appearance == nil)
        #expect(doc.tasks.count == 1)
    }

    @Test func exportOmitsTombstonesKey() throws {
        let ctx = try makeContext()
        ctx.insert(TodoTask(title: "A"))
        try ctx.save()

        let data = try SyncService.exportData(context: ctx, includeSettings: false)
        let doc = try SyncService.parse(data)
        #expect(doc.tasks.count == 1)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("tombstones"))
    }
}
