import Foundation
import SwiftData

enum SyncError: Error, Equatable {
    case unsupportedVersion(Int)
}

struct SyncReport {
    var tasksInserted = 0
    var tasksUpdated = 0
    var columnsInserted = 0
    var columnsUpdated = 0
    var dayPlansInserted = 0
    var dayPlansUpdated = 0
    var settingsApplied = false

    var totalInserted: Int { tasksInserted + columnsInserted + dayPlansInserted }
    var totalUpdated: Int { tasksUpdated + columnsUpdated + dayPlansUpdated }
}

@MainActor
enum SyncService {
    static func exportData(context: ModelContext,
                           includeSettings: Bool = true,
                           now: Date = .now) throws -> Data {
        let tasks   = try context.fetch(FetchDescriptor<TodoTask>())
        let columns = try context.fetch(FetchDescriptor<BoardColumn>())
        let plans   = try context.fetch(FetchDescriptor<DayPlan>())
        let doc = SyncDocument(
            schemaVersion: SyncDocument.currentSchemaVersion,
            exportedAt: now,
            tasks: tasks.map(SyncTaskDTO.init),
            columns: columns.map(SyncColumnDTO.init),
            dayPlans: plans.map(SyncDayPlanDTO.init),
            settings: includeSettings ? SyncSettings.snapshot() : SyncSettingsDTO()
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

    /// 按 ID 合并(DayPlan 按归一化 day),最新者胜;文件中不存在的本地记录一律保留,删除不传播。
    /// 刻意用普通 save() 以保留文件时间戳。
    @discardableResult
    static func merge(_ doc: SyncDocument, into context: ModelContext,
                      includeSettings: Bool, calendar: Calendar = .current) throws -> SyncReport {
        var report = SyncReport()

        // 本地映射(task / column)
        let cols = try context.fetch(FetchDescriptor<BoardColumn>())
        var colByID = Dictionary(uniqueKeysWithValues: cols.map { ($0.id, $0) })
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        var taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // 列(先于任务,使 columnID 引用可解析)
        for dto in doc.columns {
            if let local = colByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.columnsUpdated += 1 }
            } else {
                let c = dto.makeModel(); context.insert(c); colByID[dto.id] = c; report.columnsInserted += 1
            }
        }

        // 任务
        for dto in doc.tasks {
            if let local = taskByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.tasksUpdated += 1 }
            } else {
                let t = dto.makeModel(); context.insert(t); taskByID[dto.id] = t; report.tasksInserted += 1
            }
        }

        // 日计划(按 day 匹配)
        var plans = try context.fetch(FetchDescriptor<DayPlan>())
        for dto in doc.dayPlans {
            let day = calendar.startOfDay(for: dto.day)
            if let local = plans.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                if dto.modifiedAt > local.modifiedAt {
                    dto.apply(to: local)
                    report.dayPlansUpdated += 1
                }
            } else {
                let p = dto.makeModel()
                p.day = day
                context.insert(p); plans.append(p); report.dayPlansInserted += 1
            }
        }

        if includeSettings { SyncSettings.apply(doc.settings); report.settingsApplied = true }

        TagStore(context: context).reconcileFromTasks()
        try context.save()
        return report
    }
}
