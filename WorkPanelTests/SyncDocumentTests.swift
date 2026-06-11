import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncDocumentTests {
    @Test func taskDTORoundTripsAllFields() throws {
        let t = TodoTask(title: "标题", notes: "备注", priority: .high,
                         tags: ["x", "y"], recurrence: .weekly,
                         createdAt: Date(timeIntervalSince1970: 50))
        t.deadline = Date(timeIntervalSince1970: 100)
        t.isCompleted = true
        t.completedAt = Date(timeIntervalSince1970: 200)
        t.snoozedUntil = Date(timeIntervalSince1970: 300)
        t.columnID = UUID()
        t.boardOrder = 5
        t.planOrder = 7
        t.urgencyOverride = true
        t.modifiedAt = Date(timeIntervalSince1970: 400)

        let dto = SyncTaskDTO(t)
        let data = try SyncDocument.encoder.encode(dto)
        let back = try SyncDocument.decoder.decode(SyncTaskDTO.self, from: data)

        #expect(back.id == t.id)
        #expect(back.title == "标题")
        #expect(back.recurrenceRaw == "weekly")
        #expect(back.priorityRaw == Priority.high.rawValue)
        #expect(back.deadline == Date(timeIntervalSince1970: 100))
        #expect(back.completedAt == Date(timeIntervalSince1970: 200))
        #expect(back.snoozedUntil == Date(timeIntervalSince1970: 300))
        #expect(back.columnID == t.columnID)
        #expect(back.boardOrder == 5)
        #expect(back.planOrder == 7)
        #expect(back.urgencyOverride == true)
        #expect(back.modifiedAt == Date(timeIntervalSince1970: 400))
        #expect(back.createdAt == Date(timeIntervalSince1970: 50))
    }

    @Test func nilOptionalsRoundTrip() throws {
        let t = TodoTask(title: "空可选")     // deadline/completedAt/... 全 nil
        let dto = SyncTaskDTO(t)
        let data = try SyncDocument.encoder.encode(dto)
        let back = try SyncDocument.decoder.decode(SyncTaskDTO.self, from: data)
        #expect(back.deadline == nil)
        #expect(back.completedAt == nil)
        #expect(back.recurrenceRaw == nil)
        #expect(back.urgencyOverride == nil)
        #expect(back.columnID == nil)
    }

    @Test func columnDTORoundTrips() throws {
        let c = BoardColumn(name: "开发中", order: 2)
        c.modifiedAt = Date(timeIntervalSince1970: 111)
        let dto = SyncColumnDTO(c)
        let back = try SyncDocument.decoder.decode(
            SyncColumnDTO.self, from: try SyncDocument.encoder.encode(dto))
        #expect(back.id == c.id)
        #expect(back.name == "开发中")
        #expect(back.order == 2)
        #expect(back.modifiedAt == Date(timeIntervalSince1970: 111))
    }

    @Test func dayPlanDTORoundTrips() throws {
        let ids = [UUID(), UUID()]
        let p = DayPlan(day: Date(timeIntervalSince1970: 86400), committedTaskIDs: ids)
        p.modifiedAt = Date(timeIntervalSince1970: 222)
        let dto = SyncDayPlanDTO(p)
        let back = try SyncDocument.decoder.decode(
            SyncDayPlanDTO.self, from: try SyncDocument.encoder.encode(dto))
        #expect(back.day == Date(timeIntervalSince1970: 86400))
        #expect(back.committedTaskIDs == ids)
        #expect(back.modifiedAt == Date(timeIntervalSince1970: 222))
    }

    @Test func tombstoneDTORoundTrips() throws {
        let t = Tombstone(id: UUID(), kind: .column, deletedAt: Date(timeIntervalSince1970: 123))
        let dto = SyncTombstoneDTO(t)
        let data = try SyncDocument.encoder.encode(dto)
        let back = try SyncDocument.decoder.decode(SyncTombstoneDTO.self, from: data)
        #expect(back.id == t.id)
        #expect(back.kind == "column")
        #expect(back.deletedAt == Date(timeIntervalSince1970: 123))
        #expect(back.makeModel().kind == .column)
    }

    @Test func documentMissingTombstonesDecodesAsNil() throws {
        // tombstones 为 nil → 编码省略该键(模拟旧版本文档)→ 解码回 nil
        let doc = SyncDocument(schemaVersion: 1, exportedAt: Date(timeIntervalSince1970: 0),
                               tasks: [], columns: [], dayPlans: [], settings: SyncSettingsDTO())
        let data = try SyncDocument.encoder.encode(doc)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("tombstones"))
        let back = try SyncDocument.decoder.decode(SyncDocument.self, from: data)
        #expect(back.tombstones == nil)
    }

    @Test func tombstoneDTOUnknownKindFallsBackToTask() throws {
        var dto = SyncTombstoneDTO(Tombstone(id: UUID(), kind: .task, deletedAt: Date(timeIntervalSince1970: 1)))
        dto.kind = "unknown_future_kind"
        #expect(dto.makeModel().kind == .task)
    }

    @Test func taskDTORoundTripsStartDate() throws {
        let t = TodoTask(title: "带范围")
        t.startDate = Date(timeIntervalSince1970: 60)
        t.deadline = Date(timeIntervalSince1970: 100)
        let back = try SyncDocument.decoder.decode(
            SyncTaskDTO.self, from: try SyncDocument.encoder.encode(SyncTaskDTO(t)))
        #expect(back.startDate == Date(timeIntervalSince1970: 60))
    }

    @Test func taskDTOMissingStartDateDecodesAsNil() throws {
        // 模拟旧版本文档:JSON 里没有 startDate 键 → 解码回 nil
        let t = TodoTask(title: "无开始")           // startDate 为 nil
        let data = try SyncDocument.encoder.encode(SyncTaskDTO(t))
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("startDate"))
        let back = try SyncDocument.decoder.decode(SyncTaskDTO.self, from: data)
        #expect(back.startDate == nil)
    }
}
