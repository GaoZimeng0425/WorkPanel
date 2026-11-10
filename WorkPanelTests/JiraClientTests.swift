import Testing
import Foundation
@testable import WorkPanel

/// JiraClient 解析层:fixture 驱动,不发网络。HTTP/URLSession 层为薄实现,不测。
struct JiraClientTests {

    // MARK: - fixture 构造

    private func issueJSON(key: String,
                           summary: String? = "标题",
                           statusCategory: String? = "Indeterminate",
                           statusName: String? = "待办",
                           priority: String? = "Medium",
                           duedate: String? = nil,
                           description: [String: Any]? = nil) -> [String: Any] {
        var fields: [String: Any] = ["summary": summary ?? ""]
        if let sc = statusCategory {
            fields["status"] = ["name": statusName ?? "", "statusCategory": ["key": sc]]
        }
        if let p = priority {
            fields["priority"] = ["name": p]
        }
        if let d = duedate {
            fields["duedate"] = d
        }
        if let desc = description {
            fields["description"] = desc
        }
        return ["key": key, "fields": fields]
    }

    private func responseData(issues: [[String: Any]], nextPageToken: String? = nil) throws -> Data {
        var body: [String: Any] = ["issues": issues]
        if let t = nextPageToken { body["nextPageToken"] = t }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func para(_ texts: String...) -> [String: Any] {
        ["type": "doc", "content": texts.map { ["type": "paragraph", "content": [["type": "text", "text": $0]]] }]
    }

    // MARK: - parseIssues

    @Test func parseExtractsCoreFields() throws {
        let data = try responseData(issues: [issueJSON(
            key: "PROJ-123",
            summary: "修复登录超时",
            statusCategory: "Done",
            statusName: "已解决",
            priority: "High",
            duedate: "2026-11-20",
            description: para("描述第一段")
        )])
        let (issues, token) = try JiraClient.parseIssues(data)
        #expect(issues.count == 1)
        #expect(token == nil)
        let i = try #require(issues.first)
        #expect(i.key == "PROJ-123")
        #expect(i.summary == "修复登录超时")
        #expect(i.statusCategoryKey == "Done")
        #expect(i.statusName == "已解决")
        #expect(i.projectKey == "PROJ")
        #expect(i.priorityName == "High")
        #expect(i.duedateDay == "2026-11-20")
        #expect(i.descriptionText == "描述第一段")
    }

    @Test func parseHandlesMissingOptionals() throws {
        let data = try responseData(issues: [issueJSON(key: "X-1", summary: "s", priority: nil)])
        let (issues, _) = try JiraClient.parseIssues(data)
        let i = try #require(issues.first)
        #expect(i.priorityName == nil)
        #expect(i.duedateDay == nil)
        #expect(i.descriptionText == nil)
        #expect(i.statusCategoryKey == "Indeterminate")   // statusCategory 仍有
    }

    @Test func parseExtractsNestedADFText() throws {
        // doc → 两个 paragraph,各含两个 text 节点;段间 "\n\n",段内直接拼接
        let nested: [String: Any] = [
            "type": "doc",
            "content": [
                ["type": "paragraph", "content": [
                    ["type": "text", "text": "行内一"],
                    ["type": "text", "text": "行内二"],
                ]],
                ["type": "paragraph", "content": [
                    ["type": "text", "text": "第二段"],
                ]],
            ]
        ]
        let data = try responseData(issues: [issueJSON(key: "X-2", description: nested)])
        let (issues, _) = try JiraClient.parseIssues(data)
        #expect(issues.first?.descriptionText == "行内一行内二\n\n第二段")
    }

    @Test func parseReturnsNextPageToken() throws {
        let data = try responseData(issues: [issueJSON(key: "X-3")], nextPageToken: "next-abc")
        let (_, token) = try JiraClient.parseIssues(data)
        #expect(token == "next-abc")
    }

    // MARK: - search 分页上限与截断反馈

    /// 注入单页请求替身:每次返回 50 条 + nextPageToken;search 应在 5 页(250 条)后停止并报告截断。
    @Test func paginationCapStopsAtFivePages() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            var count: Int { lock.lock(); defer { lock.unlock() }; return n }
            func bump() { lock.lock(); n += 1; lock.unlock() }
        }
        let counter = Counter()
        let pageData = try responseData(issues: (1...50).map { issueJSON(key: "K-\($0)") },
                                        nextPageToken: "always-more")

        let client = JiraClient { _ in
            counter.bump()
            return pageData
        }
        let result = try await client.search(jql: "assignee = currentUser()")
        #expect(result.issues.count == 250)
        #expect(counter.count == 5)
        #expect(result.truncated == true)   // 仍有下一页但已到上限
    }

    @Test func searchWithoutMorePagesIsNotTruncated() async throws {
        let pageData = try responseData(issues: [issueJSON(key: "K-1")])   // 无 nextPageToken
        let client = JiraClient { _ in pageData }
        let result = try await client.search(jql: "x")
        #expect(result.issues.count == 1)
        #expect(result.truncated == false)
    }

    // MARK: - 域名校验

    @Test func searchOnInvalidDomainThrowsWithoutNetwork() async throws {
        // 含空格的域名(如粘贴带了尾随空格或敲错)不得让 URL(string:)! 崩掉整个 app
        let client = JiraClient(domain: "antalpha atlassian net", email: "e", apiToken: "t")
        await #expect(throws: JiraError.self) {
            _ = try await client.search(jql: "x")
        }
    }

    @Test func normalizedDomainTrimsAndStripsScheme() throws {
        #expect(JiraClient.normalizedDomain("  https://antalpha.atlassian.net/ ") == "antalpha.atlassian.net")
        #expect(JiraClient.normalizedDomain("antalpha.atlassian.net") == "antalpha.atlassian.net")
        #expect(JiraClient.normalizedDomain("bad domain") == nil)
    }

    // MARK: - Epic 父链接

    @Test func parseExtractsEpicParentName() throws {
        var j = issueJSON(key: "AAA-1")
        var f = j["fields"] as! [String: Any]
        f["parent"] = [
            "key": "AAA-100",
            "fields": ["summary": "1.5 图形化改造", "issuetype": ["name": "Epic"]]
        ] as [String: Any]
        j["fields"] = f
        let (issues, _) = try JiraClient.parseIssues(try responseData(issues: [j]))
        #expect(issues.first?.epicName == "1.5 图形化改造")
    }

    @Test func parseIgnoresNonEpicParent() throws {
        var j = issueJSON(key: "AAA-2")
        var f = j["fields"] as! [String: Any]
        f["parent"] = [
            "key": "AAA-200",
            "fields": ["summary": "某个普通父任务", "issuetype": ["name": "Story"]]
        ] as [String: Any]
        j["fields"] = f
        let (issues, _) = try JiraClient.parseIssues(try responseData(issues: [j]))
        #expect(issues.first?.epicName == nil)   // 只有 Epic 类型的父才标记
    }

    // MARK: - 嵌套 ADF

    @Test func parseExtractsNestedListItemsWithSeparators() throws {
        // bulletList → listItem → paragraph 的嵌套块:文本之间要有分隔,不能粘成一串
        let list: [String: Any] = [
            "type": "doc",
            "content": [
                ["type": "bulletList", "content": [
                    ["type": "listItem", "content": [
                        ["type": "paragraph", "content": [["type": "text", "text": "步骤一"]]],
                    ]],
                    ["type": "listItem", "content": [
                        ["type": "paragraph", "content": [["type": "text", "text": "步骤二"]]],
                    ]],
                ]],
            ]
        ]
        let data = try responseData(issues: [issueJSON(key: "X-9", description: list)])
        let (issues, _) = try JiraClient.parseIssues(data)
        #expect(issues.first?.descriptionText == "步骤一\n步骤二")
    }
}
