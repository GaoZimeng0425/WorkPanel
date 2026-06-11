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
    var tasksDeleted = 0
    var columnsDeleted = 0
    var settingsApplied = false

    var totalInserted: Int { tasksInserted + columnsInserted + dayPlansInserted }
    var totalUpdated: Int { tasksUpdated + columnsUpdated + dayPlansUpdated }
    var totalDeleted: Int { tasksDeleted + columnsDeleted }
}

@MainActor
enum SyncService {
    static func exportData(context: ModelContext,
                           includeSettings: Bool = true,
                           now: Date = .now) throws -> Data {
        let tasks   = try context.fetch(FetchDescriptor<TodoTask>())
        let columns = try context.fetch(FetchDescriptor<BoardColumn>())
        let plans   = try context.fetch(FetchDescriptor<DayPlan>())
        let tombs   = try context.fetch(FetchDescriptor<Tombstone>())
        let doc = SyncDocument(
            schemaVersion: SyncDocument.currentSchemaVersion,
            exportedAt: now,
            tasks: tasks.map(SyncTaskDTO.init),
            columns: columns.map(SyncColumnDTO.init),
            dayPlans: plans.map(SyncDayPlanDTO.init),
            settings: includeSettings ? SyncSettings.snapshot() : SyncSettingsDTO(),
            tombstones: tombs.map(SyncTombstoneDTO.init)
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

    /// 按 ID 合并(DayPlan 按归一化 day),最新者胜;墓碑传播删除并抑制复活。
    /// 刻意用普通 save() 以保留文件时间戳。
    @discardableResult
    static func merge(_ doc: SyncDocument, into context: ModelContext,
                      includeSettings: Bool, calendar: Calendar = .current) throws -> SyncReport {
        var report = SyncReport()

        // 本地映射(task / column / 墓碑),供墓碑阶段与抑制判断复用
        let existingTombs = try context.fetch(FetchDescriptor<Tombstone>())
        var tombByID = Dictionary(uniqueKeysWithValues: existingTombs.map { ($0.id, $0) })
        let cols = try context.fetch(FetchDescriptor<BoardColumn>())
        var colByID = Dictionary(uniqueKeysWithValues: cols.map { ($0.id, $0) })
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        var taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // 阶段一:合并传入墓碑,并按(合并后的)墓碑时间删除同类型本地记录
        for dto in doc.tombstones ?? [] {
            let local: Tombstone
            if let existing = tombByID[dto.id] {
                if dto.deletedAt > existing.deletedAt { existing.deletedAt = dto.deletedAt }
                local = existing
            } else {
                local = dto.makeModel(); context.insert(local); tombByID[dto.id] = local
            }
            let at = local.deletedAt
            // 按 kind 区分命名空间:任务墓碑只删任务,列墓碑只删列
            if local.kind == .task, let task = taskByID[dto.id], task.modifiedAt <= at {
                context.delete(task); taskByID[dto.id] = nil; report.tasksDeleted += 1
            }
            if local.kind == .column, let col = colByID[dto.id], col.modifiedAt <= at {
                context.delete(col); colByID[dto.id] = nil; report.columnsDeleted += 1
            }
        }

        // 列(先于任务,使 columnID 引用可解析)
        for dto in doc.columns {
            if let tomb = tombByID[dto.id], tomb.kind == .column, tomb.deletedAt >= dto.modifiedAt { continue }   // 删除胜
            if let local = colByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.columnsUpdated += 1 }
            } else {
                let c = dto.makeModel(); context.insert(c); colByID[dto.id] = c; report.columnsInserted += 1
            }
            if let tomb = tombByID[dto.id], tomb.kind == .column, dto.modifiedAt > tomb.deletedAt {
                context.delete(tomb); tombByID[dto.id] = nil   // 复活:撤销被超越的列墓碑
            }
        }

        // 任务
        for dto in doc.tasks {
            if let tomb = tombByID[dto.id], tomb.kind == .task, tomb.deletedAt >= dto.modifiedAt { continue }   // 删除胜
            if let local = taskByID[dto.id] {
                if dto.modifiedAt > local.modifiedAt { dto.apply(to: local); report.tasksUpdated += 1 }
            } else {
                let t = dto.makeModel(); context.insert(t); taskByID[dto.id] = t; report.tasksInserted += 1
            }
            if let tomb = tombByID[dto.id], tomb.kind == .task, dto.modifiedAt > tomb.deletedAt {
                context.delete(tomb); tombByID[dto.id] = nil   // 复活:撤销被超越的任务墓碑
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
