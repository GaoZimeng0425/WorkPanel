import Testing
import Foundation
import SwiftData
@testable import WorkPanel

/// JiraPullService 合并规则测试:in-memory 容器 + 脚本化 fake fetcher,不发网络。
@MainActor
struct JiraPullServiceTests {

    // MARK: - 基座

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, Tag.self, DayPlan.self,
                                           configurations: config)
        return ModelContext(container)
    }

    private func issue(key: String,
                       summary: String = "远端标题",
                       statusCategoryKey: String = "Indeterminate",
                       priorityName: String? = "Medium",
                       duedateDay: String? = nil,
                       descriptionText: String? = nil) -> JiraIssue {
        JiraIssue(key: key, summary: summary, statusCategoryKey: statusCategoryKey,
                  priorityName: priorityName, duedateDay: duedateDay, descriptionText: descriptionText)
    }

    /// 按脚本逐次返回;记录每次收到的 jql。首查可配置抛错。
    actor FakeFetcher: JiraFetching {
        private var scripts: [[JiraIssue]] = []
        private var _calls: [String] = []
        private var firstThrows: Error?

        init(scripts: [[JiraIssue]] = [], firstThrows: Error? = nil) {
            self.scripts = scripts
            self.firstThrows = firstThrows
        }

        var calls: [String] { _calls }

        /// 追加后续各次调用的返回脚本。
        func schedules(_ pages: [JiraIssue]...) {
            scripts.append(contentsOf: pages)
        }

        func search(jql: String) async throws -> [JiraIssue] {
            _calls.append(jql)
            if let e = firstThrows { firstThrows = nil; throw e }
            return scripts.isEmpty ? [] : scripts.removeFirst()
        }
    }

    private struct TestError: LocalizedError {
        var errorDescription: String? { "邮箱/API Token 无效(401)" }
    }

    private func pull(_ fetcher: FakeFetcher, into ctx: ModelContext,
                      dismissed: [String] = [], now: Date = Date(timeIntervalSince1970: 1000)) async -> JiraPullReport {
        await JiraPullService(fetcher: fetcher).pull(context: ctx, dismissedKeys: dismissed, now: now)
    }

    private func allTasks(_ ctx: ModelContext) throws -> [TodoTask] {
        try ctx.fetch(FetchDescriptor<TodoTask>())
    }

    // MARK: - 插入

    @Test func newIssueInsertsTaskWithKeyPrefixAndJiraTag() async throws {
        let ctx = try makeContext()
        let r = await pull(FakeFetcher(scripts: [[issue(key: "PROJ-1", summary: "修复登录",
                                                        priorityName: "High", duedateDay: "2026-11-20",
                                                        descriptionText: "描述")]]), into: ctx)
        #expect(r == JiraPullReport(inserted: 1))
        let tasks = try allTasks(ctx)
        #expect(tasks.count == 1)
        let t = try #require(tasks.first)
        #expect(t.title == "[PROJ-1] 修复登录")
        #expect(t.notes == "描述")
        #expect(t.tags == ["jira"])
        #expect(t.jiraKey == "PROJ-1")
        #expect(t.columnID == nil)
        #expect(t.priority == .high)
        #expect(t.isCompleted == false)
        #expect(t.jiraSyncedAt == Date(timeIntervalSince1970: 1000))
    }

    @Test func newDoneIssueInsertsAsCompleted() async throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 2000)
        let r = await pull(FakeFetcher(scripts: [[issue(key: "A-1", statusCategoryKey: "Done")]]),
                           into: ctx, now: now)
        #expect(r == JiraPullReport(inserted: 1))
        let t = try #require(try allTasks(ctx).first)
        #expect(t.isCompleted == true)
        #expect(t.completedAt == now)
    }

    // MARK: - 更新与本地优先

    @Test func secondPullUpdatesUnchangedLocalTask() async throws {
        let ctx = try makeContext()
        let fetcher = FakeFetcher(scripts: [[issue(key: "A-1", summary: "旧标题")]])
        _ = await pull(fetcher, into: ctx, now: Date(timeIntervalSince1970: 1000))
        await fetcher.schedules([issue(key: "A-1", summary: "新标题")])
        let r = await pull(fetcher, into: ctx, now: Date(timeIntervalSince1970: 2000))
        #expect(r == JiraPullReport(updated: 1))
        let t = try #require(try allTasks(ctx).first)
        #expect(t.title == "[A-1] 新标题")
        #expect(t.modifiedAt == Date(timeIntervalSince1970: 2000))
        #expect(t.jiraSyncedAt == Date(timeIntervalSince1970: 2000))
    }

    @Test func locallyModifiedTaskWinsOnPull() async throws {
        let ctx = try makeContext()
        let fetcher = FakeFetcher(scripts: [[issue(key: "A-1", summary: "旧标题")]])
        _ = await pull(fetcher, into: ctx, now: Date(timeIntervalSince1970: 1000))
        // 本地改过:modifiedAt > jiraSyncedAt
        let t = try #require(try allTasks(ctx).first)
        t.title = "我的本地改"
        t.modifiedAt = Date(timeIntervalSince1970: 1500)
        await fetcher.schedules([issue(key: "A-1", summary: "远端新标题")])
        let r = await pull(fetcher, into: ctx, now: Date(timeIntervalSince1970: 2000))
        #expect(r == JiraPullReport(skipped: 1))
        #expect(t.title == "我的本地改")
        #expect(t.jiraSyncedAt == Date(timeIntervalSince1970: 1000))   // 基准不动
    }

    // MARK: - 完成单向收敛

    @Test func completedLocalTaskStaysCompleted() async throws {
        let ctx = try makeContext()
        let t = TodoTask(title: "[A-1] 本地任务")
        t.jiraKey = "A-1"
        t.isCompleted = true
        t.completedAt = Date(timeIntervalSince1970: 500)
        ctx.insert(t)
        try ctx.save()
        let r = await pull(FakeFetcher(scripts: [[issue(key: "A-1", statusCategoryKey: "Indeterminate")]]),
                           into: ctx)
        #expect(r == JiraPullReport(skipped: 1))
        #expect(t.isCompleted == true)
    }

    @Test func remoteDoneCompletesLocalTask() async throws {
        let ctx = try makeContext()
        let t = TodoTask(title: "[A-1] 本地任务")
        t.jiraKey = "A-1"
        t.jiraSyncedAt = Date(timeIntervalSince1970: 1000)
        t.modifiedAt = Date(timeIntervalSince1970: 1000)
        ctx.insert(t)
        try ctx.save()
        let now = Date(timeIntervalSince1970: 2000)
        let r = await pull(FakeFetcher(scripts: [[issue(key: "A-1", statusCategoryKey: "Done")]]),
                           into: ctx, now: now)
        #expect(r == JiraPullReport(completed: 1))
        #expect(t.isCompleted == true)
        #expect(t.completedAt == now)
        #expect(t.modifiedAt == now)
        #expect(t.jiraSyncedAt == Date(timeIntervalSince1970: 1000))   // 不动
    }

    @Test func remoteDoneOnLocallyModifiedTaskCompletesWithoutLosingProtection() async throws {
        let ctx = try makeContext()
        let t = TodoTask(title: "我的本地改")
        t.jiraKey = "A-1"
        t.jiraSyncedAt = Date(timeIntervalSince1970: 1000)
        t.modifiedAt = Date(timeIntervalSince1970: 1500)   // 本地改过
        ctx.insert(t)
        try ctx.save()
        let r = await pull(FakeFetcher(scripts: [[issue(key: "A-1", statusCategoryKey: "Done")]]),
                           into: ctx, now: Date(timeIntervalSince1970: 2000))
        #expect(r == JiraPullReport(completed: 1))
        #expect(t.isCompleted == true)
        #expect(t.title == "我的本地改")                            // 字段未被覆盖
        #expect(t.jiraSyncedAt == Date(timeIntervalSince1970: 1000)) // 保护仍在,下轮本地优先
    }

    // MARK: - 二段闭单

    @Test func absentClosedIssueGetsCompletedViaSecondQuery() async throws {
        let ctx = try makeContext()
        let fetcher = FakeFetcher(scripts: [[issue(key: "A-1", statusCategoryKey: "Indeterminate")]])
        _ = await pull(fetcher, into: ctx, now: Date(timeIntervalSince1970: 1000))
        // 第二轮:主 JQL 已不返回该 issue(默认 JQL 排除 Done),二段查询返回其 Done 状态
        await fetcher.schedules([], [issue(key: "A-1", statusCategoryKey: "Done")])
        let r = await pull(fetcher, into: ctx, now: Date(timeIntervalSince1970: 2000))
        #expect(r == JiraPullReport(completed: 1))
        let t = try #require(try allTasks(ctx).first)
        #expect(t.isCompleted == true)
        let calls = await fetcher.calls
        #expect(calls.count == 3)   // 首轮 1 次(主查询命中,无二段);第二轮主查询 + 二段各 1 次
        #expect(try #require(calls.last).contains("issuekey IN"))
    }

    // MARK: - denylist

    @Test func dismissedKeyIsNotReinserted() async throws {
        let ctx = try makeContext()
        let r = await pull(FakeFetcher(scripts: [[issue(key: "D-1")]]),
                           into: ctx, dismissed: ["D-1"])
        #expect(r == JiraPullReport())
        #expect(try allTasks(ctx).isEmpty)
    }

    // MARK: - 重复任务与失败

    @Test func duplicateLocalTasksPickEarliest() async throws {
        let ctx = try makeContext()
        let old = TodoTask(title: "本地旧", createdAt: Date(timeIntervalSince1970: 100))
        old.jiraKey = "A-1"
        old.jiraSyncedAt = Date(timeIntervalSince1970: 1000)
        old.modifiedAt = Date(timeIntervalSince1970: 1000)
        let new = TodoTask(title: "本地新", createdAt: Date(timeIntervalSince1970: 200))
        new.jiraKey = "A-1"
        new.jiraSyncedAt = Date(timeIntervalSince1970: 1000)
        new.modifiedAt = Date(timeIntervalSince1970: 1000)
        ctx.insert(old); ctx.insert(new)
        try ctx.save()
        let r = await pull(FakeFetcher(scripts: [[issue(key: "A-1", summary: "远端")]]), into: ctx)
        #expect(r == JiraPullReport(updated: 1))
        #expect(old.title == "[A-1] 远端")   // 较早一条被更新
        #expect(new.title == "本地新")        // 另一条不动
    }

    @Test func authFailureLeavesStoreUntouchedAndReports() async throws {
        let ctx = try makeContext()
        let existing = TodoTask(title: "已有任务")
        ctx.insert(existing)
        try ctx.save()
        let r = await pull(FakeFetcher(firstThrows: TestError()), into: ctx)
        #expect(r.failedMessage?.contains("401") == true)
        #expect(r.inserted == 0 && r.updated == 0 && r.completed == 0 && r.skipped == 0)
        let tasks = try allTasks(ctx)
        #expect(tasks.count == 1 && tasks.first?.title == "已有任务")
        #expect(existing.title == "已有任务")
    }

    // MARK: - 截止日映射

    @Test func deadlineMapsToEndOfDay() async throws {
        let ctx = try makeContext()
        _ = await pull(FakeFetcher(scripts: [[issue(key: "A-1", duedateDay: "2026-11-20")]]), into: ctx)
        let t = try #require(try allTasks(ctx).first)
        let cal = Calendar.current
        let dayStart = cal.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        #expect(t.deadline == cal.date(byAdding: DateComponents(hour: 23, minute: 59), to: dayStart))
    }
}
