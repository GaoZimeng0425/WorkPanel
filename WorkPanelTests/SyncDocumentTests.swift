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

    @Test func documentWithLegacyTombstonesKeyDecodesAndIgnores() throws {
        // 旧版导出文件含 "tombstones" 键 → JSONDecoder 忽略未知键,正常解码
        let json = """
        {
          "schemaVersion" : 1,
          "exportedAt" : "2026-01-01T00:00:00Z",
          "tasks" : [
            {
              "id" : "11111111-1111-1111-1111-111111111111",
              "title" : "旧任务",
              "notes" : "",
              "priorityRaw" : 1,
              "tags" : [],
              "isCompleted" : false,
              "createdAt" : "2026-01-01T00:00:00Z",
              "boardOrder" : 0,
              "planOrder" : 0,
              "modifiedAt" : "2026-01-01T00:00:00Z"
            }
          ],
          "columns" : [],
          "dayPlans" : [],
          "settings" : {},
          "tombstones" : [
            {
              "id" : "22222222-2222-2222-2222-222222222222",
              "kind" : "task",
              "deletedAt" : "2026-01-02T00:00:00Z"
            }
          ]
        }
        """
        let doc = try SyncDocument.decoder.decode(SyncDocument.self, from: Data(json.utf8))
        #expect(doc.schemaVersion == 1)
        #expect(doc.tasks.count == 1)
        #expect(doc.tasks.first?.title == "旧任务")
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

    @Test func taskDTORoundTripsJiraFields() throws {
        let t = TodoTask(title: "x")
        t.jiraKey = "PROJ-1"
        t.jiraSyncedAt = Date(timeIntervalSince1970: 100)
        let dto = SyncTaskDTO(t)
        let data = try SyncDocument.encoder.encode(dto)
        let back = try SyncDocument.decoder.decode(SyncTaskDTO.self, from: data)
        let restored = TodoTask(title: "新模型")
        back.apply(to: restored)
        #expect(restored.jiraKey == "PROJ-1")
        #expect(restored.jiraSyncedAt == Date(timeIntervalSince1970: 100))
    }
}
