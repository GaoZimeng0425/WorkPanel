import Foundation
import SwiftData

enum SyncError: Error, Equatable {
    case unsupportedVersion(Int)
}

@MainActor
enum SyncService {
    static func exportData(context: ModelContext, now: Date = .now) throws -> Data {
        let tasks   = try context.fetch(FetchDescriptor<TodoTask>())
        let columns = try context.fetch(FetchDescriptor<BoardColumn>())
        let plans   = try context.fetch(FetchDescriptor<DayPlan>())
        let doc = SyncDocument(
            schemaVersion: SyncDocument.currentSchemaVersion,
            exportedAt: now,
            tasks: tasks.map(SyncTaskDTO.init),
            columns: columns.map(SyncColumnDTO.init),
            dayPlans: plans.map(SyncDayPlanDTO.init),
            settings: SyncSettings.snapshot()
        )
        return try SyncDocument.encoder.encode(doc)
    }

    static func parse(_ data: Data) throws -> SyncDocument {
        let doc = try SyncDocument.decoder.decode(SyncDocument.self, from: data)
        // 严格相等:暂不支持跨版本迁移,version 高于或低于 current 一律拒绝
        guard doc.schemaVersion == SyncDocument.currentSchemaVersion else {
            throw SyncError.unsupportedVersion(doc.schemaVersion)
        }
        return doc
    }
}
