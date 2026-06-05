import Foundation

struct SyncTaskDTO: Codable {
    var id: UUID
    var title: String
    var notes: String
    var deadline: Date?
    var priorityRaw: Int
    var tags: [String]
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var snoozedUntil: Date?
    var recurrenceRaw: String?
    var columnID: UUID?
    var boardOrder: Int
    var planOrder: Int
    var urgencyOverride: Bool?
    var modifiedAt: Date

    init(_ t: TodoTask) {
        id = t.id; title = t.title; notes = t.notes; deadline = t.deadline
        priorityRaw = t.priorityRaw; tags = t.tags; isCompleted = t.isCompleted
        completedAt = t.completedAt; createdAt = t.createdAt; snoozedUntil = t.snoozedUntil
        recurrenceRaw = t.recurrenceRaw; columnID = t.columnID; boardOrder = t.boardOrder
        planOrder = t.planOrder; urgencyOverride = t.urgencyOverride; modifiedAt = t.modifiedAt
    }

    func makeModel() -> TodoTask { let t = TodoTask(title: title); apply(to: t); return t }

    func apply(to t: TodoTask) {
        t.id = id; t.title = title; t.notes = notes; t.deadline = deadline
        t.priorityRaw = priorityRaw; t.tags = tags; t.isCompleted = isCompleted
        t.completedAt = completedAt; t.createdAt = createdAt; t.snoozedUntil = snoozedUntil
        t.recurrenceRaw = recurrenceRaw; t.columnID = columnID; t.boardOrder = boardOrder
        t.planOrder = planOrder; t.urgencyOverride = urgencyOverride; t.modifiedAt = modifiedAt
    }
}

struct SyncColumnDTO: Codable {
    var id: UUID
    var name: String
    var order: Int
    var modifiedAt: Date

    init(_ c: BoardColumn) { id = c.id; name = c.name; order = c.order; modifiedAt = c.modifiedAt }

    func makeModel() -> BoardColumn { let c = BoardColumn(name: name, order: order); apply(to: c); return c }
    func apply(to c: BoardColumn) { c.id = id; c.name = name; c.order = order; c.modifiedAt = modifiedAt }
}

struct SyncDayPlanDTO: Codable {
    var day: Date
    var committedTaskIDs: [UUID]
    var modifiedAt: Date

    init(_ p: DayPlan) { day = p.day; committedTaskIDs = p.committedTaskIDs; modifiedAt = p.modifiedAt }

    func makeModel() -> DayPlan {
        let p = DayPlan(day: day, committedTaskIDs: committedTaskIDs); p.modifiedAt = modifiedAt; return p
    }
}

struct SyncDocument: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var tasks: [SyncTaskDTO]
    var columns: [SyncColumnDTO]
    var dayPlans: [SyncDayPlanDTO]
    var settings: SyncSettingsDTO

    nonisolated(unsafe) static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    nonisolated(unsafe) static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
