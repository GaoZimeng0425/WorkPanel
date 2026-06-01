// WorkPanelTests/TaskDTOTests.swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct TaskDTOTests {
    @Test func priorityRoundTripsThroughAPINames() {
        #expect(Priority.high.apiName == "high")
        #expect(Priority.medium.apiName == "medium")
        #expect(Priority.low.apiName == "low")
        #expect(Priority(apiName: "high") == .high)
        #expect(Priority(apiName: "bogus") == nil)
    }

    @Test func iso8601RoundTrips() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let s = ISO8601Date.string(date)
        #expect(ISO8601Date.date(s) == date)
    }

    @Test func mapsTaskToDTO() {
        let due = Date(timeIntervalSinceNow: 3600)
        let task = TodoTask(title: "写周报", notes: "Q2", deadline: due,
                            priority: .high, tags: ["work"])
        let dto = TaskDTO(task, columnName: "开发中")
        #expect(dto.id == task.id.uuidString)
        #expect(dto.title == "写周报")
        #expect(dto.notes == "Q2")
        #expect(dto.priority == "high")
        #expect(dto.tags == ["work"])
        #expect(dto.isCompleted == false)
        #expect(dto.columnName == "开发中")
        #expect(dto.deadline == ISO8601Date.string(due))
        #expect(dto.isUrgent == true)   // due within 48h window
    }

    @Test func mapsColumnToDTO() {
        let col = BoardColumn(name: "测试中", order: 2)
        let dto = ColumnDTO(col)
        #expect(dto.id == col.id.uuidString)
        #expect(dto.name == "测试中")
        #expect(dto.order == 2)
    }

    @Test func iso8601AcceptsFractionalSeconds() {
        #expect(ISO8601Date.date("2026-06-03T09:00:00.000Z") != nil)
        #expect(ISO8601Date.date("2026-06-03T09:00:00Z") != nil)
        #expect(ISO8601Date.date("not-a-date") == nil)
    }
}
