import Foundation

/// 从 Jira Cloud 拉取的 issue 的规范化视图(合并引擎消费)。
nonisolated struct JiraIssue: Equatable, Sendable {
    var key: String               // "PROJ-123"
    var summary: String
    var statusName: String        // "待办" / "正在进行" …;状态→列映射用
    var statusCategoryKey: String // "Done" / "Indeterminate" / "New";缺省为空串(非 Done)
    var projectKey: String        // "OC"(从 key 前缀解析)
    var priorityName: String?     // priority 缺失时 nil
    var duedateDay: String?       // "2026-11-20" 原样;缺省 nil
    var descriptionText: String?  // ADF 提取的纯文本;无 description 时 nil
    var epicName: String?         // 父 Epic 的名称(如 "1.5"/"TUI");无 Epic 父时 nil
}

/// search 结果:issues + 是否因分页上限截断。
nonisolated struct JiraSearchResult: Equatable, Sendable {
    var issues: [JiraIssue]
    var truncated: Bool = false
}

nonisolated protocol JiraFetching: Sendable {
    /// 内部按 nextPageToken 分页,上限 5 页 × 50 条,超出置 truncated。
    func search(jql: String) async throws -> JiraSearchResult
}

nonisolated enum JiraError: LocalizedError {
    case invalidDomain
    case unauthorized
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidDomain: "Jira 域名无效"
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
    private static let fields = ["summary", "status", "priority", "duedate", "description", "parent"]

    /// 单页请求:入参为请求体 JSON,返回响应体。生产走 URLSession,测试注入替身。
    typealias PageSender = @Sendable ([String: Any]) async throws -> Data
    private let send: PageSender

    init(domain: String, email: String, apiToken: String) {
        let normalized = Self.normalizedDomain(domain)
        let auth = Data("\(email):\(apiToken)".utf8).base64EncodedString()
        send = { body in
            guard let normalized,
                  let url = URL(string: "https://\(normalized)/rest/api/3/search/jql") else {
                throw JiraError.invalidDomain
            }
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

    func search(jql: String) async throws -> JiraSearchResult {
        var all: [JiraIssue] = []
        var token: String? = nil
        for _ in 0..<Self.maxPages {
            var body: [String: Any] = ["jql": jql, "fields": Self.fields, "maxResults": Self.pageSize]
            if let t = token { body["nextPageToken"] = t }
            let (issues, next) = try Self.parseIssues(try await send(body))
            all.append(contentsOf: issues)
            guard let n = next else { return JiraSearchResult(issues: all) }
            token = n
        }
        return JiraSearchResult(issues: all, truncated: true)   // 仍有下一页,已到分页上限
    }

    // MARK: - 域名清洗

    /// 去首尾空白与协议前缀/尾斜杠;空串或含非法字符(URL 无法构造)返回 nil,不碰网络。
    static func normalizedDomain(_ raw: String) -> String? {
        var d = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where d.hasPrefix(prefix) { d.removeFirst(prefix.count) }
        while d.hasSuffix("/") { d.removeLast() }
        guard !d.isEmpty, URL(string: "https://\(d)") != nil else { return nil }
        return d
    }

    // MARK: - 解析

    static func parseIssues(_ data: Data) throws -> (issues: [JiraIssue], nextPageToken: String?) {
        let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
        let issues = (resp.issues ?? []).map { dto in
            JiraIssue(
                key: dto.key,
                summary: dto.fields?.summary ?? "",
                statusName: dto.fields?.status?.name ?? "",
                statusCategoryKey: dto.fields?.status?.statusCategory?.key ?? "",
                projectKey: String(dto.key.split(separator: "-").first ?? ""),
                priorityName: dto.fields?.priority?.name,
                duedateDay: dto.fields?.duedate,
                descriptionText: dto.fields?.description.map(adfPlainText),
                epicName: dto.fields?.epicParentName
            )
        }
        return (issues, resp.nextPageToken)
    }

    /// 子节点之间用 "\n" 连接的类型(列表/表格/引用等块容器);doc 用 "\n\n";
    /// 其余(paragraph 行内、heading、行内包装)子节点直接拼接。
    private static let newlineChildTypes: Set<String> = [
        "bulletList", "orderedList", "listItem", "codeBlock", "blockquote", "panel",
        "table", "tableRow", "tableCell", "tableHeader",
    ]

    /// ADF(Atlassian Document Format)→ 纯文本:
    /// 行内文本叶子直接拼接;嵌套块级子节点之间以 "\n" 分隔;根(doc)的直接子节点之间以 "\n\n" 分隔。
    static func adfPlainText(_ node: ADFNode) -> String {
        func childSeparator(of type: String?) -> String {
            if type == "doc" { return "\n\n" }
            return Self.newlineChildTypes.contains(type ?? "") ? "\n" : ""
        }
        func render(_ n: ADFNode) -> String {
            let separator = childSeparator(of: n.type)
            var parts: [String] = []
            for child in n.content ?? [] {
                let piece = child.type == "text" ? (child.text ?? "") : render(child)
                if !piece.isEmpty { parts.append(piece) }
            }
            return parts.joined(separator: separator)
        }
        return render(node)
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
    var parent: ParentDTO?
}

private nonisolated struct StatusDTO: Codable {
    var name: String?
    var statusCategory: StatusCategoryDTO?
}

private nonisolated struct StatusCategoryDTO: Codable {
    var key: String?
}

private nonisolated struct PriorityDTO: Codable {
    var name: String?
}

private nonisolated struct ParentDTO: Codable {
    var fields: ParentFieldsDTO?
}

private nonisolated struct ParentFieldsDTO: Codable {
    var summary: String?
    var issuetype: NameDTO?
}

private nonisolated struct NameDTO: Codable {
    var name: String?
}

private nonisolated extension FieldsDTO {
    /// 父级为 Epic 时返回其名称;父级缺失或非 Epic(如子任务的 Story 父)返回 nil。
    var epicParentName: String? {
        guard parent?.fields?.issuetype?.name == "Epic" else { return nil }
        return parent?.fields?.summary
    }
}
