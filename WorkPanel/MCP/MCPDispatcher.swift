// WorkPanel/MCP/MCPDispatcher.swift
import Foundation

struct MCPDispatcher {
    let handlers: MCPToolHandlers

    enum Outcome {
        case body(Data)     // a JSON-RPC response to send with 200
        case accepted       // a notification: send 202 with empty body
    }

    func handle(_ data: Data) async -> Outcome {
        guard let req = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .body(Self.error(id: .null, code: -32700, message: "Parse error"))
        }
        guard let method = req["method"]?.stringValue else {
            return .body(Self.error(id: req["id"] ?? .null, code: -32600, message: "Invalid Request"))
        }
        // Notifications have no `id`.
        guard let id = req["id"] else { return .accepted }

        switch method {
        case "initialize":
            let result: JSONValue = [
                "protocolVersion": "2025-06-18",
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

    private static func toolEntry(_ name: String, _ description: String, _ properties: JSONValue,
                                  required: JSONValue = .array([])) -> JSONValue {
        ["name": .string(name), "description": .string(description),
         "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    static let tools: [JSONValue] = [
        toolEntry("list_tasks", "List tasks with optional filters.", [
            "completed": ["type": "boolean"],
            "columnID": ["type": "string"],
            "tag": ["type": "string"],
            "priority": ["type": "string", "enum": ["low", "medium", "high"]],
            "dueBefore": ["type": "string", "description": "ISO-8601 datetime; keep tasks whose deadline is before this"],
            "startAfter": ["type": "string", "description": "ISO-8601 datetime; keep tasks whose startDate is at or after this"],
        ]),
        toolEntry("get_task", "Get a single task by id.",
             ["id": ["type": "string"]], required: ["id"]),
        toolEntry("list_columns", "List board columns.", [:]),
        toolEntry("list_jira_tasks", "List tasks pulled from Jira (all, or filtered by completion).",
             ["completed": ["type": "boolean"]]),
        toolEntry("create_task", "Create a new task.", [
            "title": ["type": "string"],
            "notes": ["type": "string"],
            "deadline": ["type": "string", "description": "ISO-8601 datetime"],
            "startDate": ["type": "string", "description": "ISO-8601 datetime"],
            "priority": ["type": "string", "enum": ["low", "medium", "high"]],
            "tags": ["type": "array", "items": ["type": "string"]],
            "columnID": ["type": "string"],
            "recurrence": ["type": "string", "enum": ["daily", "weekdays", "weekly", "monthly"]],
            "urgent": ["type": "boolean", "description": "Manual urgency override; omit for automatic (deadline-based)"],
        ], required: ["title"]),
        toolEntry("update_task", "Update fields of an existing task; only provided fields change. Send deadline/startDate/recurrence/urgent as null to clear them. completed:true completes the task (recurring tasks spawn the next occurrence), false reopens. Returns {task, next}.", [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "notes": ["type": "string"],
            "deadline": ["type": ["string", "null"], "description": "ISO-8601 datetime or null"],
            "startDate": ["type": ["string", "null"], "description": "ISO-8601 datetime or null"],
            "priority": ["type": "string", "enum": ["low", "medium", "high"]],
            "tags": ["type": "array", "items": ["type": "string"]],
            "recurrence": ["type": ["string", "null"], "enum": ["daily", "weekdays", "weekly", "monthly", nil], "description": "Recurrence rule, or null to clear"],
            "urgent": ["type": ["boolean", "null"], "description": "Manual urgency override, or null to revert to automatic"],
            "completed": ["type": "boolean", "description": "true completes (recurring tasks spawn the next occurrence), false reopens"],
        ], required: ["id"]),
        toolEntry("delete_task", "Delete a task.",
             ["id": ["type": "string"]], required: ["id"]),
        toolEntry("move_task", "Move a task to a board column (columnID:null clears status). Optional index for position.",
             ["id": ["type": "string"], "columnID": ["type": ["string", "null"]], "index": ["type": "integer"]],
             required: ["id"]),
    ]
}
