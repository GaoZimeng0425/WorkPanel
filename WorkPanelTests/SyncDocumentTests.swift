import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct SyncDocumentTests {
    @Test func taskDTORoundTripsAllFields() throws {
        let t = TodoTask(title: "标题", notes: "备注", priority: .high,
                         tags: ["x", "y"], recurrence: .weekly)
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
}
