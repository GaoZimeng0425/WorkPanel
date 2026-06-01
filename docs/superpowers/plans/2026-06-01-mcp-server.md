# Embedded MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed a zero-dependency MCP server in WorkPanel so external AI (Claude Code) can read, create, modify, and transition tasks over localhost HTTP, with system-notification sync.

**Architecture:** A tiny `Network.framework` HTTP listener bound to `127.0.0.1` accepts one JSON-RPC 2.0 message per `POST /mcp`, validates a Bearer token, and dispatches `initialize` / `tools/list` / `tools/call`. Tool calls run on the `@MainActor`, mutate the app's shared SwiftData `ModelContext` through the existing `TodoStore`/`BoardStore`, drive `ReminderScheduler` for notification sync, and return DTOs. Because the app is the single writer, the board/list UI updates live.

**Tech Stack:** Swift 6, SwiftUI/AppKit, SwiftData, `Network.framework`, Swift Testing (`import Testing`). Spec: `docs/superpowers/specs/2026-06-01-mcp-server-design.md`.

---

## Conventions (read once)

**This project uses Xcode 16 filesystem-synchronized groups.** New `.swift` files placed under `WorkPanel/` or `WorkPanelTests/` are picked up automatically — **never edit `project.pbxproj`.**

**Per-suite testing only.** A full-bundle `xcodebuild test` can wedge `testmanagerd`. Always scope to one suite:

```bash
xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel \
  -destination 'platform=macOS' \
  -only-testing:WorkPanelTests/<SuiteName> 2>&1 | tail -25
```

**Build check:**

```bash
xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel \
  -destination 'platform=macOS' 2>&1 | tail -25
```

All new production files live under `WorkPanel/MCP/`. All new tests live under `WorkPanelTests/`.

## File Structure

| File | Responsibility |
|---|---|
| `WorkPanel/MCP/JSONValue.swift` | Dynamic JSON value (Codable + literal conformances + accessors) for JSON-RPC params/results. |
| `WorkPanel/MCP/TaskDTO.swift` | `TaskDTO`/`ColumnDTO` wire contract, `Priority` API-name mapping, ISO-8601 helper. |
| `WorkPanel/MCP/HTTPMessage.swift` | Minimal HTTP/1.1 request parse + response build. |
| `WorkPanel/MCP/MCPToolHandlers.swift` | `@MainActor` tool implementations over `TodoStore`/`BoardStore` + `ReminderScheduler`. The only file touching SwiftData. |
| `WorkPanel/MCP/MCPDispatcher.swift` | JSON-RPC routing + tool catalog (names + JSON Schemas). |
| `WorkPanel/MCP/MCPServer.swift` | `NWListener` lifecycle, HTTP framing, Bearer-token gate, `.mcpSettingsChanged` notification name. |
| `WorkPanel/Store/AppSettings.swift` (modify) | `mcpEnabled` / `mcpPort` / `mcpToken` keys + accessors. |
| `WorkPanel/UI/SettingsView.swift` (modify) | "AI 接入 (MCP)" settings card. |
| `WorkPanel/WorkPanelApp.swift` (modify) | Start/stop the server in `AppDelegate`. |

---

## Task 1: JSONValue

**Files:**
- Create: `WorkPanel/MCP/JSONValue.swift`
- Test: `WorkPanelTests/JSONValueTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// WorkPanelTests/JSONValueTests.swift
import Testing
import Foundation
@testable import WorkPanel

struct JSONValueTests {
    @Test func decodesObjectAndReadsTypedAccessors() throws {
        let data = Data(#"{"title":"写文档","count":3,"done":true,"tags":["a","b"]}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(v["title"]?.stringValue == "写文档")
        #expect(v["count"]?.intValue == 3)
        #expect(v["done"]?.boolValue == true)
        #expect(v["tags"]?.arrayValue?.compactMap(\.stringValue) == ["a", "b"])
        #expect(v["missing"] == nil)
    }

    @Test func contagiousNullVsAbsent() throws {
        let data = Data(#"{"deadline":null}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(v.contains("deadline"))
        #expect(v["deadline"]?.isNull == true)
        #expect(v.contains("other") == false)
    }

    @Test func encodesViaLiterals() throws {
        let v: JSONValue = ["type": "object", "n": 1, "ok": true, "list": ["x"]]
        let data = try JSONEncoder().encode(v)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(back["type"]?.stringValue == "object")
        #expect(back["n"]?.intValue == 1)
        #expect(back["ok"]?.boolValue == true)
        #expect(back["list"]?.arrayValue?.first?.stringValue == "x")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/JSONValueTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'JSONValue' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// WorkPanel/MCP/JSONValue.swift
import Foundation

/// Minimal dynamic JSON value used for JSON-RPC params and results.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue {
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }

    subscript(_ key: String) -> JSONValue? { objectValue?[key] }
    func contains(_ key: String) -> Bool { objectValue?[key] != nil }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
                     ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
    init(nilLiteral: ()) { self = .null }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/JSONValueTests 2>&1 | tail -25`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/JSONValue.swift WorkPanelTests/JSONValueTests.swift
git commit -m "feat(mcp): add JSONValue dynamic JSON type"
```

---

## Task 2: DTOs, Priority API names, ISO-8601 helper

**Files:**
- Create: `WorkPanel/MCP/TaskDTO.swift`
- Test: `WorkPanelTests/TaskDTOTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// WorkPanelTests/TaskDTOTests.swift
import Testing
import Foundation
@testable import WorkPanel

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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TaskDTOTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'ISO8601Date'` / `value of type 'Priority' has no member 'apiName'`.

- [ ] **Step 3: Write the implementation**

```swift
// WorkPanel/MCP/TaskDTO.swift
import Foundation

enum ISO8601Date {
    static func string(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func date(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }
}

extension Priority {
    var apiName: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
    init?(apiName: String) {
        switch apiName {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        default: return nil
        }
    }
}

struct TaskDTO: Codable, Equatable {
    let id: String
    let title: String
    let notes: String
    let deadline: String?
    let priority: String
    let tags: [String]
    let isCompleted: Bool
    let completedAt: String?
    let columnID: String?
    let columnName: String?
    let boardOrder: Int
    let isUrgent: Bool

    init(_ task: TodoTask, columnName: String?, now: Date = .now) {
        id = task.id.uuidString
        title = task.title
        notes = task.notes
        deadline = task.deadline.map(ISO8601Date.string)
        priority = task.priority.apiName
        tags = task.tags
        isCompleted = task.isCompleted
        completedAt = task.completedAt.map(ISO8601Date.string)
        columnID = task.columnID?.uuidString
        self.columnName = columnName
        boardOrder = task.boardOrder
        isUrgent = task.isUrgent(asOf: now)
    }
}

struct ColumnDTO: Codable, Equatable {
    let id: String
    let name: String
    let order: Int

    init(_ column: BoardColumn) {
        id = column.id.uuidString
        name = column.name
        order = column.order
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TaskDTOTests 2>&1 | tail -25`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/TaskDTO.swift WorkPanelTests/TaskDTOTests.swift
git commit -m "feat(mcp): add TaskDTO/ColumnDTO wire contract"
```

---

## Task 3: HTTP message parse/build

**Files:**
- Create: `WorkPanel/MCP/HTTPMessage.swift`
- Test: `WorkPanelTests/HTTPMessageTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// WorkPanelTests/HTTPMessageTests.swift
import Testing
import Foundation
@testable import WorkPanel

struct HTTPMessageTests {
    @Test func parsesPostWithHeadersAndBody() {
        let raw = "POST /mcp HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer abc\r\nContent-Length: 7\r\n\r\n{\"a\":1}"
        let req = HTTPRequest.parse(Data(raw.utf8))
        #expect(req?.method == "POST")
        #expect(req?.path == "/mcp")
        #expect(req?.headers["authorization"] == "Bearer abc")   // keys lowercased
        #expect(req?.headers["content-length"] == "7")
        #expect(req?.body == Data("{\"a\":1}".utf8))
        #expect(req?.isComplete == true)
    }

    @Test func incompleteHeadersReturnNil() {
        #expect(HTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nHost: loc".utf8)) == nil)
    }

    @Test func incompleteBodyIsNotComplete() {
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort"
        #expect(HTTPRequest.parse(Data(raw.utf8))?.isComplete == false)
    }

    @Test func buildsResponses() {
        let json = HTTPResponse.json(Data("{}".utf8))
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{}"))

        #expect(String(decoding: HTTPResponse.unauthorized(), as: UTF8.self).hasPrefix("HTTP/1.1 401"))
        #expect(String(decoding: HTTPResponse.methodNotAllowed(), as: UTF8.self).hasPrefix("HTTP/1.1 405"))
        #expect(String(decoding: HTTPResponse.accepted(), as: UTF8.self).hasPrefix("HTTP/1.1 202"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/HTTPMessageTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'HTTPRequest' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// WorkPanel/MCP/HTTPMessage.swift
import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]   // keys lowercased
    let body: Data

    /// Parses an HTTP/1.1 request. Returns nil if the header block is not yet complete.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let body = data.subdata(in: headerEnd.upperBound..<data.endIndex)
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]),
                           headers: headers, body: body)
    }

    /// Whether the full body (per Content-Length) has arrived.
    var isComplete: Bool {
        let expected = Int(headers["content-length"] ?? "0") ?? 0
        return body.count >= expected
    }
}

enum HTTPResponse {
    static func build(status: Int, reason: String,
                      headers: [String: String] = [:], body: Data = Data()) -> Data {
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (k, v) in allHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    static func json(_ body: Data) -> Data {
        build(status: 200, reason: "OK",
              headers: ["Content-Type": "application/json"], body: body)
    }
    static func accepted() -> Data { build(status: 202, reason: "Accepted") }
    static func unauthorized() -> Data { build(status: 401, reason: "Unauthorized") }
    static func methodNotAllowed() -> Data { build(status: 405, reason: "Method Not Allowed") }
}
```

> Note: `build` emits headers in dictionary order, which is non-deterministic. The test only asserts on `json()` whose extra header set still produces the asserted substrings regardless of order; do not assert full-string equality on multi-header responses.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/HTTPMessageTests 2>&1 | tail -25`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/HTTPMessage.swift WorkPanelTests/HTTPMessageTests.swift
git commit -m "feat(mcp): add minimal HTTP/1.1 request parse and response build"
```

---

## Task 4: Tool handlers — read tools + skeleton

**Files:**
- Create: `WorkPanel/MCP/MCPToolHandlers.swift`
- Test: `WorkPanelTests/MCPToolHandlersTests.swift`

This task creates the handler class with the `call(_:_:)` entry point and the three read tools. Later tasks add the write/state tools to the same file and same test suite.

- [ ] **Step 1: Write the failing test**

```swift
// WorkPanelTests/MCPToolHandlersTests.swift
import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import WorkPanel

@MainActor
struct MCPToolHandlersTests {
    final class MockCenter: NotificationScheduling, @unchecked Sendable {
        var added: [UNNotificationRequest] = []
        var removed: [String] = []
        func add(_ request: UNNotificationRequest) async throws { added.append(request) }
        func removePendingNotificationRequests(withIdentifiers ids: [String]) { removed.append(contentsOf: ids) }
    }

    private func makeHandlers() throws -> (MCPToolHandlers, ModelContext, MockCenter) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        let context = ModelContext(container)
        let mock = MockCenter()
        let handlers = MCPToolHandlers(context: context, scheduler: ReminderScheduler(center: mock))
        return (handlers, context, mock)
    }

    private func decodeArray(_ json: String) throws -> [TaskDTO] {
        try JSONDecoder().decode([TaskDTO].self, from: Data(json.utf8))
    }
    private func decodeTask(_ json: String) throws -> TaskDTO {
        try JSONDecoder().decode(TaskDTO.self, from: Data(json.utf8))
    }

    @Test func listTasksFiltersByCompleted() async throws {
        let (h, ctx, _) = try makeHandlers()
        let a = TodoTask(title: "未完成")
        let b = TodoTask(title: "已完成"); b.isCompleted = true
        [a, b].forEach { ctx.insert($0) }
        try ctx.save()

        let open = try await h.call("list_tasks", ["completed": false])
        #expect(try decodeArray(open).map(\.title) == ["未完成"])

        let done = try await h.call("list_tasks", ["completed": true])
        #expect(try decodeArray(done).map(\.title) == ["已完成"])
    }

    @Test func getTaskReturnsOneAndThrowsWhenMissing() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "找我")
        ctx.insert(t); try ctx.save()

        let dto = try await h.call("get_task", ["id": .string(t.id.uuidString)])
        #expect(try decodeTask(dto).title == "找我")

        await #expect(throws: ToolError.self) {
            _ = try await h.call("get_task", ["id": .string(UUID().uuidString)])
        }
    }

    @Test func listColumnsReturnsColumns() async throws {
        let (h, ctx, _) = try makeHandlers()
        ctx.insert(BoardColumn(name: "计划中", order: 0))
        ctx.insert(BoardColumn(name: "开发中", order: 1))
        try ctx.save()

        let json = try await h.call("list_columns", .object([:]))
        let cols = try JSONDecoder().decode([ColumnDTO].self, from: Data(json.utf8))
        #expect(cols.map(\.name) == ["计划中", "开发中"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'MCPToolHandlers' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// WorkPanel/MCP/MCPToolHandlers.swift
import Foundation
import SwiftData

enum ToolError: Error, CustomStringConvertible {
    case notFound(String)
    case badArgument(String)

    var description: String {
        switch self {
        case .notFound(let m): return m
        case .badArgument(let m): return m
        }
    }
}

@MainActor
final class MCPToolHandlers {
    private let context: ModelContext
    private let todo: TodoStore
    private let board: BoardStore
    private let scheduler: ReminderScheduler

    init(context: ModelContext, scheduler: ReminderScheduler = ReminderScheduler()) {
        self.context = context
        self.todo = TodoStore(context: context)
        self.board = BoardStore(context: context)
        self.scheduler = scheduler
    }

    /// Routes an MCP tool name + arguments object to its handler, returning a JSON text payload.
    func call(_ name: String, _ args: JSONValue) async throws -> String {
        switch name {
        case "list_tasks":   return try listTasks(args)
        case "get_task":     return try getTask(args)
        case "list_columns": return try listColumns()
        default: throw ToolError.badArgument("Unknown tool: \(name)")
        }
    }

    // MARK: - Read tools

    private func listTasks(_ args: JSONValue) throws -> String {
        var tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        if let completed = args["completed"]?.boolValue {
            tasks = tasks.filter { $0.isCompleted == completed }
        }
        if let s = args["columnID"]?.stringValue, let col = UUID(uuidString: s) {
            tasks = tasks.filter { $0.columnID == col }
        }
        if let tag = args["tag"]?.stringValue {
            tasks = tasks.filter { $0.tags.contains(tag) }
        }
        if let p = args["priority"]?.stringValue, let pr = Priority(apiName: p) {
            tasks = tasks.filter { $0.priority == pr }
        }
        if let s = args["dueBefore"]?.stringValue, let date = ISO8601Date.date(s) {
            tasks = tasks.filter { ($0.deadline ?? .distantFuture) < date }
        }
        return try encode(tasks.map(dto))
    }

    private func getTask(_ args: JSONValue) throws -> String {
        try encode(dto(fetchTask(requireID(args))))
    }

    private func listColumns() throws -> String {
        try encode(board.columns().map(ColumnDTO.init))
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func columnName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return board.columns().first { $0.id == id }?.name
    }

    private func dto(_ task: TodoTask) -> TaskDTO {
        TaskDTO(task, columnName: columnName(for: task.columnID))
    }

    private func requireID(_ args: JSONValue) throws -> UUID {
        guard let s = args["id"]?.stringValue, let id = UUID(uuidString: s) else {
            throw ToolError.badArgument("Missing or invalid 'id'")
        }
        return id
    }

    private func fetchTask(_ id: UUID) throws -> TodoTask {
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        guard let task = all.first(where: { $0.id == id }) else {
            throw ToolError.notFound("No task with id \(id.uuidString)")
        }
        return task
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -25`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/MCPToolHandlers.swift WorkPanelTests/MCPToolHandlersTests.swift
git commit -m "feat(mcp): add tool handlers with read tools (list/get/columns)"
```

---

## Task 5: Tool handlers — create & update (with notification sync)

**Files:**
- Modify: `WorkPanel/MCP/MCPToolHandlers.swift`
- Modify: `WorkPanelTests/MCPToolHandlersTests.swift`

- [ ] **Step 1: Add the failing tests** (append inside the `MCPToolHandlersTests` struct, before the closing brace)

```swift
    @Test func createTaskInsertsAndSchedulesNotification() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let due = ISO8601Date.string(Date(timeIntervalSinceNow: 3600))
        let json = try await h.call("create_task", [
            "title": "写文档", "notes": "细节", "priority": "high",
            "tags": ["work"], "deadline": .string(due),
        ])
        let dto = try decodeTask(json)
        #expect(dto.title == "写文档")
        #expect(dto.priority == "high")
        #expect(dto.tags == ["work"])

        let stored = (try ctx.fetch(FetchDescriptor<TodoTask>()))
        #expect(stored.count == 1)
        #expect(mock.added.count == 1)   // future deadline → notification scheduled
        #expect(mock.added.first?.identifier == dto.id)
    }

    @Test func createTaskRequiresTitle() async throws {
        let (h, _, _) = try makeHandlers()
        await #expect(throws: ToolError.self) {
            _ = try await h.call("create_task", ["notes": "无标题"])
        }
    }

    @Test func updateTaskPatchesOnlyProvidedFieldsAndReschedules() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "旧标题", notes: "旧备注", priority: .low,
                         deadline: Date(timeIntervalSinceNow: 3600))
        ctx.insert(t); try ctx.save()

        let json = try await h.call("update_task", [
            "id": .string(t.id.uuidString), "title": "新标题", "priority": "high",
        ])
        let dto = try decodeTask(json)
        #expect(dto.title == "新标题")
        #expect(dto.priority == "high")
        #expect(dto.notes == "旧备注")   // untouched (absent key)
        #expect(mock.removed.contains(t.id.uuidString))   // cancel
        #expect(mock.added.count == 1)                    // reschedule
    }

    @Test func updateTaskClearsDeadlineWhenExplicitNull() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "有截止", deadline: Date(timeIntervalSinceNow: 3600))
        ctx.insert(t); try ctx.save()

        let json = try await h.call("update_task", ["id": .string(t.id.uuidString), "deadline": .null])
        #expect(try decodeTask(json).deadline == nil)
        #expect(t.deadline == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -25`
Expected: FAIL — `create_task` routes to `Unknown tool` and throws `ToolError`, so the create/update assertions fail.

- [ ] **Step 3: Extend the implementation**

In `call(_:_:)`, add the two cases (note `try await` — these are async):

```swift
        case "create_task":  return try await createTask(args)
        case "update_task":  return try await updateTask(args)
```

Add these methods to `MCPToolHandlers` (after `listColumns()`):

```swift
    // MARK: - Create / update

    private func createTask(_ args: JSONValue) async throws -> String {
        guard let title = args["title"]?.stringValue, !title.isEmpty else {
            throw ToolError.badArgument("Missing 'title'")
        }
        var parsed = ParsedInput()
        parsed.title = title
        parsed.priority = args["priority"]?.stringValue.flatMap(Priority.init(apiName:)) ?? .medium
        parsed.tags = args["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if let s = args["deadline"]?.stringValue, let date = ISO8601Date.date(s) {
            parsed.deadline = date
        }
        let notes = args["notes"]?.stringValue ?? ""
        let task = todo.add(parsed, notes: notes)
        if let s = args["columnID"]?.stringValue, let col = UUID(uuidString: s) {
            board.setColumn(task, to: col)
        }
        try context.save()
        await scheduler.schedule(for: task)
        return try encode(dto(task))
    }

    private func updateTask(_ args: JSONValue) async throws -> String {
        let task = try fetchTask(requireID(args))
        if let v = args["title"]?.stringValue { task.title = v }
        if let v = args["notes"]?.stringValue { task.notes = v }
        if args.contains("deadline") {
            if let s = args["deadline"]?.stringValue, let d = ISO8601Date.date(s) { task.deadline = d }
            else if args["deadline"]?.isNull == true { task.deadline = nil }
        }
        if let v = args["priority"]?.stringValue, let p = Priority(apiName: v) { task.priority = p }
        if let arr = args["tags"]?.arrayValue { task.tags = arr.compactMap(\.stringValue) }
        try context.save()
        scheduler.cancel(for: task)
        await scheduler.schedule(for: task)
        return try encode(dto(task))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -25`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/MCPToolHandlers.swift WorkPanelTests/MCPToolHandlersTests.swift
git commit -m "feat(mcp): add create_task/update_task with notification sync"
```

---

## Task 6: Tool handlers — complete / reopen / snooze / delete / move

**Files:**
- Modify: `WorkPanel/MCP/MCPToolHandlers.swift`
- Modify: `WorkPanelTests/MCPToolHandlersTests.swift`

- [ ] **Step 1: Add the failing tests** (append inside the `MCPToolHandlersTests` struct)

```swift
    struct CompleteResultDTO: Codable { let task: TaskDTO; let next: TaskDTO? }

    @Test func completeTaskCancelsNotificationAndReturnsTask() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "完成我", deadline: Date(timeIntervalSinceNow: 3600))
        ctx.insert(t); try ctx.save()

        let json = try await h.call("complete_task", ["id": .string(t.id.uuidString)])
        let result = try JSONDecoder().decode(CompleteResultDTO.self, from: Data(json.utf8))
        #expect(result.task.isCompleted == true)
        #expect(result.next == nil)
        #expect(mock.removed.contains(t.id.uuidString))
    }

    @Test func completeRecurringSchedulesNext() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "每天站会", deadline: Date(timeIntervalSinceNow: 3600), recurrence: .daily)
        ctx.insert(t); try ctx.save()

        let json = try await h.call("complete_task", ["id": .string(t.id.uuidString)])
        let result = try JSONDecoder().decode(CompleteResultDTO.self, from: Data(json.utf8))
        #expect(result.next != nil)
        #expect(mock.added.contains { $0.identifier == result.next?.id })
    }

    @Test func reopenClearsCompletion() async throws {
        let (h, ctx, _) = try makeHandlers()
        let t = TodoTask(title: "恢复我"); t.isCompleted = true; t.completedAt = .now
        ctx.insert(t); try ctx.save()

        let dto = try decodeTask(try await h.call("reopen_task", ["id": .string(t.id.uuidString)]))
        #expect(dto.isCompleted == false)
    }

    @Test func snoozeSetsSnoozeWithoutTouchingNotifications() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "推迟我")
        ctx.insert(t); try ctx.save()
        let until = ISO8601Date.string(Date(timeIntervalSinceNow: 86400))

        _ = try await h.call("snooze_task", ["id": .string(t.id.uuidString), "until": .string(until)])
        #expect(t.snoozedUntil != nil)
        #expect(mock.added.isEmpty && mock.removed.isEmpty)   // snooze never touches notifications
    }

    @Test func deleteRemovesTaskAndNotification() async throws {
        let (h, ctx, mock) = try makeHandlers()
        let t = TodoTask(title: "删除我")
        ctx.insert(t); try ctx.save()

        let json = try await h.call("delete_task", ["id": .string(t.id.uuidString)])
        #expect(json.contains(t.id.uuidString))
        #expect((try ctx.fetch(FetchDescriptor<TodoTask>())).isEmpty)
        #expect(mock.removed.contains(t.id.uuidString))
    }

    @Test func moveTaskSetsColumnAndOrder() async throws {
        let (h, ctx, _) = try makeHandlers()
        let c0 = BoardColumn(name: "A", order: 0)
        let c1 = BoardColumn(name: "B", order: 1)
        [c0, c1].forEach { ctx.insert($0) }
        let t = TodoTask(title: "移动我"); t.columnID = c0.id
        ctx.insert(t); try ctx.save()

        let dto = try decodeTask(try await h.call("move_task", [
            "id": .string(t.id.uuidString), "columnID": .string(c1.id.uuidString), "index": 0,
        ]))
        #expect(dto.columnID == c1.id.uuidString)
        #expect(dto.columnName == "B")
    }

    @Test func moveTaskClearsColumnWhenNull() async throws {
        let (h, ctx, _) = try makeHandlers()
        let c0 = BoardColumn(name: "A", order: 0); ctx.insert(c0)
        let t = TodoTask(title: "清状态"); t.columnID = c0.id
        ctx.insert(t); try ctx.save()

        let dto = try decodeTask(try await h.call("move_task", [
            "id": .string(t.id.uuidString), "columnID": .null,
        ]))
        #expect(dto.columnID == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -25`
Expected: FAIL — the five new tools route to `Unknown tool`.

- [ ] **Step 3: Extend the implementation**

In `call(_:_:)`, add the cases (`complete_task` is async; the rest are sync):

```swift
        case "complete_task": return try await completeTask(args)
        case "reopen_task":   return try reopenTask(args)
        case "snooze_task":   return try snoozeTask(args)
        case "delete_task":   return try deleteTask(args)
        case "move_task":     return try moveTask(args)
```

Add a result wrapper at file scope (top level, near `ToolError`):

```swift
struct CompleteResult: Codable {
    let task: TaskDTO
    let next: TaskDTO?
}
```

Add these methods to `MCPToolHandlers`:

```swift
    // MARK: - State transitions

    private func completeTask(_ args: JSONValue) async throws -> String {
        let task = try fetchTask(requireID(args))
        let next = todo.complete(task)
        try context.save()
        scheduler.cancel(for: task)
        if let next { await scheduler.schedule(for: next) }
        return try encode(CompleteResult(task: dto(task), next: next.map(dto)))
    }

    private func reopenTask(_ args: JSONValue) throws -> String {
        let task = try fetchTask(requireID(args))
        todo.reopen(task)
        try context.save()
        return try encode(dto(task))
    }

    private func snoozeTask(_ args: JSONValue) throws -> String {
        guard let s = args["until"]?.stringValue, let date = ISO8601Date.date(s) else {
            throw ToolError.badArgument("Missing or invalid 'until'")
        }
        let task = try fetchTask(requireID(args))
        todo.snooze(task, until: date)
        try context.save()
        return try encode(dto(task))
    }

    private func deleteTask(_ args: JSONValue) throws -> String {
        let id = try requireID(args)
        let task = try fetchTask(id)
        scheduler.cancel(for: task)
        todo.delete(task)
        try context.save()
        return try encode(["deleted": id.uuidString])
    }

    private func moveTask(_ args: JSONValue) throws -> String {
        let task = try fetchTask(requireID(args))
        if args.contains("columnID"), args["columnID"]?.isNull == true {
            board.setColumn(task, to: nil)
        } else if let s = args["columnID"]?.stringValue, let col = UUID(uuidString: s) {
            if let index = args["index"]?.intValue {
                board.move(task, to: col, at: index)
            } else {
                board.setColumn(task, to: col)
            }
        } else {
            throw ToolError.badArgument("Missing 'columnID'")
        }
        try context.save()
        return try encode(dto(task))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPToolHandlersTests 2>&1 | tail -25`
Expected: PASS (14 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/MCPToolHandlers.swift WorkPanelTests/MCPToolHandlersTests.swift
git commit -m "feat(mcp): add complete/reopen/snooze/delete/move tools"
```

---

## Task 7: JSON-RPC dispatcher + tool catalog

**Files:**
- Create: `WorkPanel/MCP/MCPDispatcher.swift`
- Test: `WorkPanelTests/MCPDispatcherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// WorkPanelTests/MCPDispatcherTests.swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct MCPDispatcherTests {
    private func makeDispatcher() throws -> MCPDispatcher {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, DayPlan.self, configurations: config)
        return MCPDispatcher(handlers: MCPToolHandlers(context: ModelContext(container)))
    }

    private func send(_ d: MCPDispatcher, _ body: JSONValue) async throws -> JSONValue {
        let data = try JSONEncoder().encode(body)
        guard case .body(let out) = await d.handle(data) else {
            Issue.record("expected body outcome"); return .null
        }
        return try JSONDecoder().decode(JSONValue.self, from: out)
    }

    @Test func initializeReturnsServerInfo() async throws {
        let d = try makeDispatcher()
        let r = try await send(d, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                   "params": ["protocolVersion": "2025-06-18"]])
        #expect(r["result"]?["serverInfo"]?["name"]?.stringValue == "WorkPanel")
        #expect(r["result"]?["protocolVersion"]?.stringValue == "2025-06-18")
        #expect(r["result"]?["capabilities"]?["tools"] != nil)
    }

    @Test func toolsListReturnsTenTools() async throws {
        let d = try makeDispatcher()
        let r = try await send(d, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = r["result"]?["tools"]?.arrayValue ?? []
        #expect(tools.count == 10)
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        #expect(names.contains("create_task"))
        #expect(names.contains("move_task"))
    }

    @Test func toolsCallDispatchesToHandler() async throws {
        let d = try makeDispatcher()
        let r = try await send(d, ["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                   "params": ["name": "create_task", "arguments": ["title": "嗨"]]])
        let text = r["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue
        #expect(text?.contains("嗨") == true)
        #expect(r["result"]?["isError"] == nil)
    }

    @Test func toolErrorBecomesIsErrorResult() async throws {
        let d = try makeDispatcher()
        let r = try await send(d, ["jsonrpc": "2.0", "id": 4, "method": "tools/call",
                                   "params": ["name": "get_task", "arguments": ["id": "not-a-uuid"]]])
        #expect(r["result"]?["isError"]?.boolValue == true)
    }

    @Test func unknownMethodReturnsJSONRPCError() async throws {
        let d = try makeDispatcher()
        let r = try await send(d, ["jsonrpc": "2.0", "id": 5, "method": "no/such"])
        #expect(r["error"]?["code"]?.intValue == -32601)
    }

    @Test func notificationReturnsAccepted() async throws {
        let d = try makeDispatcher()
        let data = try JSONEncoder().encode(["jsonrpc": "2.0", "method": "notifications/initialized"] as JSONValue)
        if case .accepted = await d.handle(data) {} else { Issue.record("expected accepted") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPDispatcherTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'MCPDispatcher' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// WorkPanel/MCP/MCPDispatcher.swift
import Foundation

struct MCPDispatcher {
    let handlers: MCPToolHandlers

    enum Outcome {
        case body(Data)     // a JSON-RPC response to send with 200
        case accepted       // a notification: send 202 with empty body
    }

    func handle(_ data: Data) async -> Outcome {
        guard let req = try? JSONDecoder().decode(JSONValue.self, from: data),
              let method = req["method"]?.stringValue else {
            return .body(Self.error(id: .null, code: -32700, message: "Parse error"))
        }
        // Notifications have no `id`.
        guard let id = req["id"] else { return .accepted }

        switch method {
        case "initialize":
            let pv = req["params"]?["protocolVersion"]?.stringValue ?? "2025-06-18"
            let result: JSONValue = [
                "protocolVersion": .string(pv),
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "WorkPanel", "version": "1.0"],
            ]
            return .body(Self.result(id: id, result: result))

        case "ping":
            return .body(Self.result(id: id, result: [:]))

        case "tools/list":
            return .body(Self.result(id: id, result: ["tools": .array(Self.tools)]))

        case "tools/call":
            guard let name = req["params"]?["name"]?.stringValue else {
                return .body(Self.error(id: id, code: -32602, message: "Missing tool name"))
            }
            let args = req["params"]?["arguments"] ?? .object([:])
            do {
                let payload = try await handlers.call(name, args)
                let result: JSONValue = ["content": [["type": "text", "text": .string(payload)]]]
                return .body(Self.result(id: id, result: result))
            } catch {
                let result: JSONValue = [
                    "content": [["type": "text", "text": .string(String(describing: error))]],
                    "isError": true,
                ]
                return .body(Self.result(id: id, result: result))
            }

        default:
            return .body(Self.error(id: id, code: -32601, message: "Method not found"))
        }
    }

    private static func result(id: JSONValue, result: JSONValue) -> Data {
        let resp: JSONValue = ["jsonrpc": "2.0", "id": id, "result": result]
        return (try? JSONEncoder().encode(resp)) ?? Data()
    }

    private static func error(id: JSONValue, code: Int, message: String) -> Data {
        let resp: JSONValue = ["jsonrpc": "2.0", "id": id,
                               "error": ["code": .number(Double(code)), "message": .string(message)]]
        return (try? JSONEncoder().encode(resp)) ?? Data()
    }

    // MARK: - Tool catalog

    private static func task(_ name: String, _ description: String, _ properties: JSONValue,
                             required: JSONValue = .array([])) -> JSONValue {
        ["name": .string(name), "description": .string(description),
         "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    static let tools: [JSONValue] = [
        task("list_tasks", "List tasks with optional filters.", [
            "completed": ["type": "boolean"],
            "columnID": ["type": "string"],
            "tag": ["type": "string"],
            "priority": ["type": "string", "enum": ["low", "medium", "high"]],
            "dueBefore": ["type": "string", "description": "ISO-8601 datetime"],
        ]),
        task("get_task", "Get a single task by id.",
             ["id": ["type": "string"]], required: ["id"]),
        task("list_columns", "List board columns.", [:]),
        task("create_task", "Create a new task.", [
            "title": ["type": "string"],
            "notes": ["type": "string"],
            "deadline": ["type": "string", "description": "ISO-8601 datetime"],
            "priority": ["type": "string", "enum": ["low", "medium", "high"]],
            "tags": ["type": "array", "items": ["type": "string"]],
            "columnID": ["type": "string"],
        ], required: ["title"]),
        task("update_task", "Update fields of an existing task; only provided fields change. Send deadline:null to clear it.", [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "notes": ["type": "string"],
            "deadline": ["type": ["string", "null"], "description": "ISO-8601 datetime or null"],
            "priority": ["type": "string", "enum": ["low", "medium", "high"]],
            "tags": ["type": "array", "items": ["type": "string"]],
        ], required: ["id"]),
        task("complete_task", "Mark a task complete; returns the next occurrence if it recurs.",
             ["id": ["type": "string"]], required: ["id"]),
        task("reopen_task", "Reopen a completed task.",
             ["id": ["type": "string"]], required: ["id"]),
        task("snooze_task", "Snooze a task until a date (ISO-8601).",
             ["id": ["type": "string"], "until": ["type": "string"]], required: ["id", "until"]),
        task("delete_task", "Delete a task.",
             ["id": ["type": "string"]], required: ["id"]),
        task("move_task", "Move a task to a board column (columnID:null clears status). Optional index for position.",
             ["id": ["type": "string"], "columnID": ["type": ["string", "null"]], "index": ["type": "integer"]],
             required: ["id"]),
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPDispatcherTests 2>&1 | tail -25`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/MCPDispatcher.swift WorkPanelTests/MCPDispatcherTests.swift
git commit -m "feat(mcp): add JSON-RPC dispatcher and 10-tool catalog"
```

---

## Task 8: HTTP server (NWListener) + token gate

**Files:**
- Create: `WorkPanel/MCP/MCPServer.swift`
- Test: `WorkPanelTests/MCPServerAuthTests.swift`

The socket layer is verified manually (Task 11); only the pure token check is unit-tested (per the project's no-flaky-socket-tests rule).

- [ ] **Step 1: Write the failing test**

```swift
// WorkPanelTests/MCPServerAuthTests.swift
import Testing
@testable import WorkPanel

struct MCPServerAuthTests {
    @Test func acceptsMatchingBearerToken() {
        #expect(MCPServer.authorized(["authorization": "Bearer secret"], token: "secret"))
    }
    @Test func rejectsMissingOrWrongToken() {
        #expect(MCPServer.authorized([:], token: "secret") == false)
        #expect(MCPServer.authorized(["authorization": "Bearer nope"], token: "secret") == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPServerAuthTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'MCPServer' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// WorkPanel/MCP/MCPServer.swift
import Foundation
import Network

extension Notification.Name {
    /// Posted by SettingsView when MCP enable/port changes so AppDelegate can restart the server.
    static let mcpSettingsChanged = Notification.Name("mcpSettingsChanged")
}

@MainActor
final class MCPServer {
    private let port: UInt16
    private let token: String
    private let dispatcher: MCPDispatcher
    private var listener: NWListener?

    init(port: UInt16, token: String, handlers: MCPToolHandlers) {
        self.port = port
        self.token = token
        self.dispatcher = MCPDispatcher(handlers: handlers)
    }

    static func authorized(_ headers: [String: String], token: String) -> Bool {
        headers["authorization"] == "Bearer \(token)"
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback   // bind 127.0.0.1 only
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: params, on: nwPort) else { return }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: .main)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isDone, error in
            guard let self else { return }
            var acc = buffer
            if let data { acc.append(data) }
            if let req = HTTPRequest.parse(acc), req.isComplete {
                Task { @MainActor in await self.respond(conn, to: req) }
            } else if isDone || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buffer: acc)
            }
        }
    }

    private func respond(_ conn: NWConnection, to req: HTTPRequest) async {
        let response: Data
        if req.method == "GET" {
            response = HTTPResponse.methodNotAllowed()
        } else if !Self.authorized(req.headers, token: token) {
            response = HTTPResponse.unauthorized()
        } else {
            switch await dispatcher.handle(req.body) {
            case .body(let data): response = HTTPResponse.json(data)
            case .accepted: response = HTTPResponse.accepted()
            }
        }
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }
}
```

> **Swift 6 concurrency note:** `NWConnection` is a reference type that may not satisfy `Sendable` when captured into the `Task { @MainActor in ... }` inside `receive`. If the compiler flags this, the simplest fix is to keep everything on `.main`: the listener and connections already run on `queue: .main`, so the receive completion is effectively main-thread. Replace the `Task { @MainActor in await self.respond(...) }` with a direct `MainActor.assumeIsolated { Task { await self.respond(conn, to: req) } }`, or mark the receive path with `nonisolated(unsafe)` captures. See `docs/macos/02-swift6-concurrency.md` for the project's established patterns. This is the one task expected to need concurrency tuning during implementation.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/MCPServerAuthTests 2>&1 | tail -25`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/MCP/MCPServer.swift WorkPanelTests/MCPServerAuthTests.swift
git commit -m "feat(mcp): add NWListener HTTP server with Bearer-token gate"
```

---

## Task 9: AppSettings keys + token generation

**Files:**
- Modify: `WorkPanel/Store/AppSettings.swift`
- Modify: `WorkPanelTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing test** (append inside `AppSettingsTests`; if it is a `@MainActor struct`, keep style consistent — add the test method as-is)

```swift
    @Test func mcpTokenGeneratesOnceAndPersists() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppSettings.Key.mcpToken)
        let first = AppSettings.mcpToken
        #expect(!first.isEmpty)
        #expect(AppSettings.mcpToken == first)   // stable across reads
        defaults.removeObject(forKey: AppSettings.Key.mcpToken)   // cleanup
    }

    @Test func mcpPortDefaultsTo8787() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.mcpPort)
        #expect(AppSettings.mcpPort == 8787)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AppSettingsTests 2>&1 | tail -25`
Expected: FAIL — `type 'AppSettings.Key' has no member 'mcpToken'`.

- [ ] **Step 3: Modify `AppSettings.swift`**

Add to the `Key` enum:

```swift
        static let mcpEnabled = "mcpEnabled"
        static let mcpPort = "mcpPort"
        static let mcpToken = "mcpToken"
```

Add to the `register(defaults:)` dictionary in `registerDefaults()`:

```swift
            Key.mcpEnabled: false,
            Key.mcpPort: 8787,
```

Add these accessors (after `appearance`):

```swift
    static var mcpEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.mcpEnabled)
    }
    static var mcpPort: Int {
        let p = UserDefaults.standard.integer(forKey: Key.mcpPort)
        return p == 0 ? 8787 : p
    }
    static var mcpToken: String {
        if let t = UserDefaults.standard.string(forKey: Key.mcpToken), !t.isEmpty { return t }
        let t = UUID().uuidString
        UserDefaults.standard.set(t, forKey: Key.mcpToken)
        return t
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AppSettingsTests 2>&1 | tail -25`
Expected: PASS (existing tests + 2 new).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Store/AppSettings.swift WorkPanelTests/AppSettingsTests.swift
git commit -m "feat(mcp): add MCP enable/port/token settings"
```

---

## Task 10: Settings UI card

**Files:**
- Modify: `WorkPanel/UI/SettingsView.swift`

UI-only; verified visually in Task 11. No unit test.

- [ ] **Step 1: Add state bindings** (after the existing `@AppStorage` lines, ~line 11)

```swift
    @AppStorage(AppSettings.Key.mcpEnabled) private var mcpEnabled = false
    @AppStorage(AppSettings.Key.mcpPort) private var mcpPort = 8787
    @State private var mcpToken = AppSettings.mcpToken
```

- [ ] **Step 2: Add the section** (insert a new `section(...)` block between the "提醒" section and the trailing "完成" `HStack`)

```swift
            section("AI 接入 (MCP)", systemImage: "sparkles") {
                row("启用本地服务", systemImage: "network") {
                    Toggle("", isOn: $mcpEnabled)
                        .labelsHidden().toggleStyle(.switch)
                        .onChange(of: mcpEnabled) { _, _ in
                            NotificationCenter.default.post(name: .mcpSettingsChanged, object: nil)
                        }
                }
                divider
                row("端口", systemImage: "number") {
                    TextField("", value: $mcpPort, format: .number.grouping(.never))
                        .labelsHidden().frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            NotificationCenter.default.post(name: .mcpSettingsChanged, object: nil)
                        }
                }
                divider
                row("连接地址", systemImage: "link") {
                    Text("http://127.0.0.1:\(mcpPort)/mcp")
                        .font(.callout.monospaced()).foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                divider
                row("访问令牌", systemImage: "key") {
                    Button("复制令牌") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mcpToken, forType: .string)
                    }
                    .buttonStyle(NoirPillButtonStyle())
                }
            }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -25`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add WorkPanel/UI/SettingsView.swift
git commit -m "feat(mcp): add MCP settings card with toggle/port/url/token"
```

---

## Task 11: Wire server into AppDelegate + manual end-to-end verification

**Files:**
- Modify: `WorkPanel/WorkPanelApp.swift`

- [ ] **Step 1: Add the server property** (in `AppDelegate`, near the other `private let` controllers)

```swift
    private var mcpServer: MCPServer?
```

- [ ] **Step 2: Start on launch + observe changes** (inside `applicationDidFinishLaunching`, after the existing `NotificationCenter` observers)

```swift
        NotificationCenter.default.addObserver(forName: .mcpSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartMCP() }
        }
        startOrStopMCP()
```

- [ ] **Step 3: Add the lifecycle methods** (in `AppDelegate`)

```swift
    private func startOrStopMCP() {
        if AppSettings.mcpEnabled {
            let handlers = MCPToolHandlers(context: SharedModel.container.mainContext)
            let server = MCPServer(port: UInt16(AppSettings.mcpPort),
                                   token: AppSettings.mcpToken, handlers: handlers)
            server.start()
            mcpServer = server
        } else {
            mcpServer?.stop()
            mcpServer = nil
        }
    }

    private func restartMCP() {
        mcpServer?.stop()
        mcpServer = nil
        startOrStopMCP()
    }
```

- [ ] **Step 4: Build**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -25`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Manual end-to-end check**

1. Run the app from Xcode (or `open` the built `.app`). Open Settings → "AI 接入 (MCP)" → toggle **启用本地服务** on. Copy the token (or read it: `defaults read com.<bundleid> mcpToken`).
2. From a terminal, confirm `tools/list` works (replace `<TOKEN>`):

```bash
curl -s http://127.0.0.1:8787/mcp \
  -H "Authorization: Bearer <TOKEN>" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | head -c 400
```

Expected: JSON containing `"name":"create_task"` among 10 tools.

3. Confirm the token gate:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8787/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: `401`.

4. Create a task and confirm it appears live in the board/list UI:

```bash
curl -s http://127.0.0.1:8787/mcp \
  -H "Authorization: Bearer <TOKEN>" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"来自 MCP 的任务"}}}'
```

Expected: result text contains the new task; the task shows up in WorkPanel without a manual refresh.

5. Register with Claude Code:

```bash
claude mcp add --transport http workpanel http://127.0.0.1:8787/mcp \
  --header "Authorization: Bearer <TOKEN>"
```

Then in a Claude Code session confirm the `workpanel` tools are listed and a `list_tasks` call returns data.

- [ ] **Step 6: Commit**

```bash
git add WorkPanel/WorkPanelApp.swift
git commit -m "feat(mcp): start embedded MCP server from AppDelegate"
```

---

## Done criteria (maps to spec §9)

1. `claude mcp add` connects; `tools/list` returns all 10 tools. → Task 11.5
2. Create/update/complete via MCP reflected live in UI. → Task 11.5.4
3. Future-deadline create schedules a notification; complete/delete removes it. → Tasks 5–6 (handler tests) + verified manually.
4. Requests without a valid Bearer token → `401`. → Task 8 (unit) + Task 11.5.3.
5. All suites pass via per-suite `-only-testing`: `JSONValueTests`, `TaskDTOTests`, `HTTPMessageTests`, `MCPToolHandlersTests`, `MCPDispatcherTests`, `MCPServerAuthTests`, `AppSettingsTests`.
