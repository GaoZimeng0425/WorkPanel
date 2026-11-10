import Foundation
import SwiftData

struct JiraPullReport: Equatable {
    var inserted = 0
    var updated = 0        // 远端字段更新
    var completed = 0      // 既有任务被标完成(新建即完成计 inserted)
    var skipped = 0        // 本地优先跳过(含本地已完成)
    var truncated = false  // JQL 结果超分页上限(5×50),只拉了前一部分
    var failedMessage: String?
}

/// Jira → WorkPanel 单向拉取合并引擎。规则(设计定稿):
/// - 按 `jiraKey` 去重(同 key 多条本地记录取 `createdAt` 最早)
/// - 本地改过(`modifiedAt > jiraSyncedAt`)则本地优先,跳过远端字段更新
/// - 完成单向收敛:远端 Done → 本地完成;本地已完成永不回退
/// - 二段闭单:滑出 JQL 的已关联 issue 用 `issuekey IN` 补查状态
/// - denylist 只抑制插入,更新与闭单照常
/// 时间统一用注入的 `now`;刻意用普通 `save()`(不用 saveTracking),打点由本服务显式控制。
@MainActor
struct JiraPullService {
    private let fetcher: any JiraFetching

    init(fetcher: any JiraFetching) { self.fetcher = fetcher }

    func pull(context: ModelContext, dismissedKeys: [String], now: Date = .now) async -> JiraPullReport {
        var report = JiraPullReport()
        let dismissed = Set(dismissedKeys)

        let remoteResult: JiraSearchResult
        do {
            remoteResult = try await fetcher.search(jql: AppSettings.jiraJQL)
        } catch {
            report.failedMessage = "拉取失败:\(error.localizedDescription)"
            return report
        }
        report.truncated = remoteResult.truncated
        let remote = remoteResult.issues

        // 本地 jiraKey 索引;同 key 多条取 createdAt 最早为目标
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        var targetByKey: [String: TodoTask] = [:]
        for t in tasks {
            guard let k = t.jiraKey else { continue }
            if let existing = targetByKey[k], existing.createdAt <= t.createdAt { continue }
            targetByKey[k] = t
        }

        var remoteKeys = Set<String>()
        for issue in remote {
            remoteKeys.insert(issue.key)
            if let local = targetByKey[issue.key] {
                if local.isCompleted { report.skipped += 1; continue }          // 完成永不回退
                if issue.statusCategoryKey == "Done" {
                    markCompleted(local, now: now)                              // 不动 jiraSyncedAt,保住本地保护
                    report.completed += 1
                    continue
                }
                if local.modifiedAt > (local.jiraSyncedAt ?? local.modifiedAt) {
                    report.skipped += 1; continue                               // 本地改过,本地优先
                }
                apply(issue, to: local, now: now)
                report.updated += 1
            } else {
                guard !dismissed.contains(issue.key) else { continue }          // 删除过的不再插入
                let t = TodoTask(title: "")
                apply(issue, to: t, now: now)
                t.jiraKey = issue.key
                if issue.statusCategoryKey == "Done" { markCompleted(t, now: now) }
                context.insert(t)
                targetByKey[issue.key] = t
                report.inserted += 1
            }
        }

        // 二段闭单:已关联、未完成、且不在本次结果的 key(不排除 dismissed,避免数据陈旧)
        let absent = targetByKey
            .filter { !$0.value.isCompleted && !remoteKeys.contains($0.key) }
            .keys.sorted().prefix(50)
        if !absent.isEmpty {
            let jql = "issuekey IN (" + absent.joined(separator: ", ") + ")"
            if let statuses = try? await fetcher.search(jql: jql) {
                let doneKeys = Set(statuses.issues.filter { $0.statusCategoryKey == "Done" }.map(\.key))
                if !doneKeys.isEmpty {
                    // await 期间用户可能删除过任务:重新 fetch,拿到的都是活实例(已删的自然不在)
                    let live = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
                    for local in live where local.jiraKey.map(doneKeys.contains) == true {
                        guard !local.isCompleted else { continue }
                        markCompleted(local, now: now)
                        report.completed += 1
                    }
                }
            }
        }

        TagStore(context: context).reconcileFromTasks()
        do { try context.save() }
        catch { report.failedMessage = "拉取完成,但写入存储失败:\(error.localizedDescription)" }
        return report
    }

    // MARK: - 字段映射

    /// 远端字段应用到任务(插入与更新共用)。不触碰 isCompleted/completedAt/columnID/recurrence 等。
    private func apply(_ issue: JiraIssue, to t: TodoTask, now: Date) {
        t.title = "[\(issue.key)] \(issue.summary)"
        t.notes = issue.descriptionText ?? ""
        t.deadline = Self.deadline(fromDay: issue.duedateDay)
        t.priority = Self.priority(from: issue.priorityName)
        t.tags = ["jira"]
        t.modifiedAt = now
        t.jiraSyncedAt = now
    }

    private func markCompleted(_ t: TodoTask, now: Date) {
        t.isCompleted = true
        t.completedAt = now
        t.modifiedAt = now   // 抬 modifiedAt 让导出/导入按 newest-wins 携带;jiraSyncedAt 刻意不动
    }

    /// Highest/Critical/High → high;Low/Lowest → low;其余(含 Medium、nil、站内自定义名)→ medium。
    private static func priority(from name: String?) -> Priority {
        switch name {
        case "Highest", "Critical", "High": .high
        case "Low", "Lowest": .low
        default: .medium
        }
    }

    /// "yyyy-MM-dd"(本地时区当日 00:00)折算为当日 23:59。
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func deadline(fromDay day: String?) -> Date? {
        guard let day, let start = dayFormatter.date(from: day) else { return nil }
        return Calendar.current.date(byAdding: DateComponents(hour: 23, minute: 59), to: start)
    }
}
