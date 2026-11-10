import Foundation

/// 从 Jira Cloud 拉取的 issue 的规范化视图(合并引擎消费)。
nonisolated struct JiraIssue: Equatable, Sendable {
    var key: String               // "PROJ-123"
    var summary: String
    var statusCategoryKey: String // "Done" / "Indeterminate" / "New";缺省为空串(非 Done)
    var priorityName: String?     // priority 缺失时 nil
    var duedateDay: String?       // "2026-11-20" 原样;缺省 nil
    var descriptionText: String?  // ADF 提取的纯文本;无 description 时 nil
}

nonisolated protocol JiraFetching: Sendable {
    /// 内部按 nextPageToken 分页,上限 5 页 × 50 条。
    func search(jql: String) async throws -> [JiraIssue]
}

nonisolated enum JiraError: LocalizedError {
    case unauthorized
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "邮箱/API Token 无效(401)"
        case .http(let code): "Jira 请求失败(HTTP \(code))"
        }
    }
}

/// Jira Cloud REST v3 客户端:POST /rest/api/3/search/jql,Basic 鉴权。
/// 网络层为薄实现;解析与分页逻辑静态化,供测试直测。
nonisolated struct JiraClient: JiraFetching {
    static let maxPages = 5
    static let pageSize = 50
    private static let fields = ["summary", "status", "priority", "duedate", "description"]

    /// 单页请求:入参为请求体 JSON,返回响应体。生产走 URLSession,测试注入替身。
    typealias PageSender = @Sendable ([String: Any]) async throws -> Data
    private let send: PageSender

    init(domain: String, email: String, apiToken: String) {
        let url = URL(string: "https://\(domain)/rest/api/3/search/jql")!
        let auth = Data("\(email):\(apiToken)".utf8).base64EncodedString()
        send = { body in
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw code == 401 ? JiraError.unauthorized : JiraError.http(code)
            }
            return data
        }
    }

    /// 测试用初始化:替身直接产出响应体。
    init(pageSender: @escaping PageSender) { send = pageSender }

    func search(jql: String) async throws -> [JiraIssue] {
        var all: [JiraIssue] = []
        var token: String? = nil
        for _ in 0..<Self.maxPages {
            var body: [String: Any] = ["jql": jql, "fields": Self.fields, "maxResults": Self.pageSize]
            if let t = token { body["nextPageToken"] = t }
            let (issues, next) = try Self.parseIssues(try await send(body))
            all.append(contentsOf: issues)
            guard let n = next else { break }
            token = n
        }
        return all
    }

    // MARK: - 解析

    static func parseIssues(_ data: Data) throws -> (issues: [JiraIssue], nextPageToken: String?) {
        let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
        let issues = (resp.issues ?? []).map { dto in
            JiraIssue(
                key: dto.key,
                summary: dto.fields?.summary ?? "",
                statusCategoryKey: dto.fields?.status?.statusCategory?.key ?? "",
                priorityName: dto.fields?.priority?.name,
                duedateDay: dto.fields?.duedate,
                descriptionText: dto.fields?.description.map(adfPlainText)
            )
        }
        return (issues, resp.nextPageToken)
    }

    /// ADF(Atlassian Document Format)→ 纯文本:文本叶子直接拼接,
    /// 根的直接子节点(段落等)各成一段,段间以 "\n\n" 连接。
    static func adfPlainText(_ node: ADFNode) -> String {
        func inline(_ n: ADFNode) -> String {
            var s = n.text ?? ""
            for c in n.content ?? [] { s += inline(c) }
            return s
        }
        return (node.content ?? []).map(inline).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// ADF 节点:只取 text 与 content,其余(marks/attrs)忽略。
nonisolated struct ADFNode: Codable {
    var type: String?
    var text: String?
    var content: [ADFNode]?
}

private nonisolated struct SearchResponse: Codable {
    var issues: [IssueDTO]?
    var nextPageToken: String?
}

private nonisolated struct IssueDTO: Codable {
    var key: String
    var fields: FieldsDTO?
}

private nonisolated struct FieldsDTO: Codable {
    var summary: String?
    var status: StatusDTO?
    var priority: PriorityDTO?
    var duedate: String?
    var description: ADFNode?
}

private nonisolated struct StatusDTO: Codable {
    var statusCategory: StatusCategoryDTO?
}

private nonisolated struct StatusCategoryDTO: Codable {
    var key: String?
}

private nonisolated struct PriorityDTO: Codable {
    var name: String?
}
