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
