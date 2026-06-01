# Embedded MCP Server for WorkPanel — Design

**Date:** 2026-06-01
**Status:** Approved (pending spec review)

## Goal

Expose WorkPanel's work items (`TodoTask`) to external AI agents (Claude Code / Claude
Desktop) so they can read, create, modify, and transition the state of tasks. The
integration is a Model Context Protocol (MCP) server embedded directly in the WorkPanel
app, served over localhost HTTP.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Integration mechanism | MCP server |
| Where it runs | Embedded in the WorkPanel app (single SwiftData writer) |
| Transport | Streamable HTTP, bound to `127.0.0.1` |
| Implementation | Hand-rolled, zero new dependencies (`Network.framework` + `Codable`) |
| Operation scope | Read, create, modify, state transitions |
| Security | `127.0.0.1` binding **and** Bearer token |
| Reminder (notification) sync | **In v1** — handlers mirror the UI's `schedule`/`cancel` behavior (see §4.1) |
| Token storage | `UserDefaults` (via `AppSettings`) |

## 1. Architecture

WorkPanel embeds a tiny HTTP server (`Network.framework`, no external deps) bound to
`127.0.0.1:PORT`. It speaks MCP's Streamable HTTP transport in its simplest form: each
`POST /mcp` carries one JSON-RPC 2.0 message, and the server replies with a single JSON
object (`Content-Type: application/json`). No SSE stream is used — every tool is plain
request/response.

```
Claude Code ──HTTP POST /mcp──▶ NWListener (127.0.0.1)
  (Bearer token)                  │ validate token → 401 if bad
                                  │ decode JSON-RPC
                                  ▼
                          MCPDispatcher  ──await MainActor──▶ TodoStore / BoardStore
                          (initialize,                         (SwiftData, single writer)
                           tools/list,                              │
                           tools/call)                              ▼
                                  ◀──── JSON-RPC result ◀── DTO mapping (no @Model leaks)
```

Because the app is the single writer to `SharedModel.container`, every tool mutation flows
through the same `ModelContext` the UI observes, so the board/list update live with no
explicit refresh.

### Transport details (stateless)

- `POST /mcp` with a JSON-RPC request → single JSON response (`200`, `application/json`).
- `POST /mcp` with a JSON-RPC **notification** (e.g. `notifications/initialized`, no `id`)
  → `202 Accepted`, empty body.
- `GET /mcp` (client trying to open an SSE stream) → `405 Method Not Allowed`. This is
  allowed by the spec when the server offers no server-initiated streaming.
- Sessionless: no `Mcp-Session-Id` tracking. `initialize` advertises only `tools`
  capability. Claude Code tolerates a stateless server.
- Missing/invalid `Authorization: Bearer <token>` → `401 Unauthorized` **before** any
  JSON-RPC parsing.

## 2. New files

All under a new `WorkPanel/MCP/` group.

| File | Responsibility |
|---|---|
| `MCPServer.swift` | `NWListener` lifecycle (start/stop), accept connections, read one HTTP/1.1 request, write one HTTP response. Bearer-token check → 401. No MCP semantics. |
| `HTTPMessage.swift` | Minimal HTTP/1.1 request parse (method, path, headers, body) + response build. Pure, unit-testable. |
| `MCPDispatcher.swift` | JSON-RPC 2.0 layer. Routes `initialize`, `notifications/initialized`, `tools/list`, `tools/call`. Owns the tool catalog (names + JSON Schemas). Returns a `Codable` JSON-RPC response. |
| `MCPToolHandlers.swift` | The `@MainActor` task operations — bridges tool args → `TodoStore`/`BoardStore`, drives `ReminderScheduler` (notification sync, §4.1), maps results to DTOs. The only file that touches SwiftData. |
| `TaskDTO.swift` | `Codable` DTOs (`TaskDTO`, `ColumnDTO`) — the external JSON contract, decoupled from the `@Model`. |

`MCPServer`/`HTTPMessage` are domain-ignorant (reusable transport). `MCPToolHandlers` is
the only domain-coupled piece, so domain logic is independently testable.

## 3. DTOs

```json
TaskDTO {
  "id": "UUID",
  "title": "string",
  "notes": "string",
  "deadline": "2026-06-03T09:00:00Z",   // ISO-8601, nullable
  "priority": "low|medium|high",
  "tags": ["string"],
  "isCompleted": false,
  "completedAt": null,                   // ISO-8601, nullable
  "columnID": "UUID",                    // nullable (no board status)
  "columnName": "开发中",                 // resolved for readability, nullable
  "boardOrder": 0,
  "isUrgent": true                       // computed via TodoTask.isUrgent()
}

ColumnDTO {
  "id": "UUID",
  "name": "string",
  "order": 0
}
```

Dates serialize as ISO-8601 (`ISO8601DateFormatter`). `priority` serializes as the
lowercase case name, not the raw Int.

## 4. Tool surface (10 tools)

| Tool | Args | Maps to |
|---|---|---|
| `list_tasks` | `completed?`, `columnID?`, `tag?`, `priority?`, `dueBefore?` (all optional filters) | fetch + filter → `[TaskDTO]` |
| `get_task` | `id` (req) | fetch one → `TaskDTO` (error if not found) |
| `list_columns` | — | `BoardStore.columns()` → `[ColumnDTO]` |
| `create_task` | `title` (req), `notes?`, `deadline?`, `priority?`, `tags?`, `columnID?` | build `ParsedInput` → `TodoStore.add` → `TaskDTO` |
| `update_task` | `id` (req) + any of `title/notes/deadline/priority/tags` | partial patch (see below) → `TaskDTO` |
| `complete_task` | `id` (req) | `TodoStore.complete`; result includes the next occurrence `TaskDTO` if it recurs |
| `reopen_task` | `id` (req) | `TodoStore.reopen` → `TaskDTO` |
| `snooze_task` | `id` (req), `until` (ISO-8601, req) | `TodoStore.snooze` → `TaskDTO` |
| `delete_task` | `id` (req) | `TodoStore.delete` → `{ "deleted": "<id>" }` |
| `move_task` | `id` (req), `columnID` (nullable), `index?` | `BoardStore.move` (with index) / `setColumn` (no index) → `TaskDTO` |

### Partial patch semantics for `update_task`

Only keys present in the call are changed; an absent key leaves the field untouched. This
requires distinguishing "key absent" from "key present with null". Implementation: decode
into an args struct that tracks presence per field (e.g. decode the raw JSON object and
check `containsKey`, or use a presence-wrapping property wrapper). A `null` deadline
explicitly clears it; an absent deadline leaves it as-is.

### Tool result shape

Each `tools/call` returns MCP content blocks: a single `type: "text"` block whose text is
the JSON-encoded DTO (or array/object). Tool-level failures (e.g. unknown id, bad date)
return `isError: true` with a human-readable message, not a transport-level error.

### 4.1 Notification sync

`MCPToolHandlers` holds a `ReminderScheduler` — the same pattern the views already use
(`TaskListView`, `KanbanLensView`, etc.); the scheduler is stateless (it wraps
`UNUserNotificationCenter.current()`), so a fresh instance is correct. The handler's init
defaults to `ReminderScheduler()` but accepts an injected one, so tests can pass
`ReminderScheduler(center: fakeCenter)` (using the existing `NotificationScheduling`
protocol) and assert add/remove calls. After
mutating the store, each tool calls the scheduler exactly where the equivalent UI action
does, so MCP-driven changes keep system notifications in lockstep with the app:

| Tool | Notification action (mirrors UI) |
|---|---|
| `create_task` | `await schedule(for: task)` |
| `update_task` | `cancel(for: task)` then `await schedule(for: task)` (mirrors editor save — covers deadline/title/notes changes) |
| `complete_task` | `cancel(for: task)`; if it recurs, `await schedule(for: next)` |
| `delete_task` | `cancel(for: task)` |
| `reopen_task` | none — matches UI (reopen does not reschedule) |
| `snooze_task` | none — matches UI; `snooze` only sets `snoozedUntil` (list visibility), it never touched `deadline`/notifications |
| `get_task` / `list_tasks` / `list_columns` / `move_task` | none (no deadline change) |

`ReminderScheduler.schedule` already no-ops safely for completed tasks, missing deadlines,
or past fire dates, so handlers can call it unconditionally after a mutation.

Authorization: the app already requests notification permission at launch
(`AppDelegate`). Handlers do not re-request; if permission was denied, `schedule` simply
fails silently inside the scheduler, same as the UI today.

## 5. Settings & lifecycle

`AppSettings` gains three keys (all in `UserDefaults`):

- `mcpEnabled: Bool` — default **off**.
- `mcpPort: Int` — default `8787`.
- `mcpToken: String` — generated once on first access if empty (UUID-based).

`SettingsView` gets a frosted card consistent with the rest of the app:

- enable toggle,
- port field,
- the full connect URL (`http://127.0.0.1:<port>/mcp`),
- the token with a copy button,
- a one-line hint: `claude mcp add --transport http workpanel http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"`.

`AppDelegate.applicationDidFinishLaunching` starts the server iff `mcpEnabled`. Toggling the
setting starts/stops the listener live (observe the setting change → call
`MCPServer.start()`/`stop()`).

## 6. Concurrency

`NWListener` callbacks fire on a background `DispatchQueue`. SwiftData
(`SharedModel.container.mainContext`) is `@MainActor`. Therefore:

- `MCPServer` parses HTTP off-main and holds listener state (an `actor`, or a class pinned
  to a dedicated serial queue).
- The dispatcher's tool calls are `async` and `await MainActor.run { … }` for every store
  touch.
- No locks, no shared mutable state across the boundary.

## 7. Out of scope for v1

- Keychain storage for the token (UserDefaults is used instead).
- Column create/rename/delete/reorder tools (board structure editing). Only `list_columns`
  and `move_task` are exposed in v1.
- Server-initiated streaming / SSE, MCP sessions, MCP resources & prompts.

## 8. Testing strategy

Per-suite tests (the project avoids full-bundle `xcodebuild test` runs that wedge
testmanagerd):

- **`HTTPMessageTests`** — parse a raw request buffer; build a response; round-trip.
- **`MCPDispatcherTests`** — feed `initialize` / `tools/list` / `tools/call` JSON, assert
  JSON-RPC envelopes and error codes; assert the 401 path when token is missing/wrong.
- **`MCPToolHandlersTests`** — in-memory `ModelContainer` (the `--uitest` pattern) plus a
  fake `NotificationScheduling` injected into the handler's `ReminderScheduler`. Call each
  tool handler, assert store mutations, DTO output, **and** the expected notification
  add/remove calls per §4.1 (e.g. `create_task` with a future deadline adds a request;
  `complete_task`/`delete_task` remove it). Primary coverage lives here.

The `NWListener` socket layer stays thin and is verified manually (`curl` +
`claude mcp add`); no flaky socket tests.

## 9. Success criteria

1. With the server enabled, `claude mcp add` connects and `tools/list` returns all 10
   tools.
2. Creating/updating/completing a task via MCP is reflected live in the board/list UI.
3. A task created/edited via MCP with a future deadline produces a pending system
   notification; completing or deleting it via MCP removes that pending notification
   (verified manually, or via a `NotificationScheduling` test double in the handler tests).
4. Requests without a valid Bearer token receive `401`.
5. All three test suites pass via per-suite `-only-testing`.
