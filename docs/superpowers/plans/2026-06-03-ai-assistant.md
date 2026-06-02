# AI 助手(出站 LLM) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 WorkPanel 增加一个出站 AI 助手:可配置 OpenAI 兼容的 baseURL/模型/API Key 与多个自定义 prompt,在单任务上「梳理拓展」(预览后写入 notes),在复盘透镜里「总结所有未完成工作」。

**Architecture:** 单个 `AIService`(MainActor)构造 OpenAI 兼容的 `POST {baseURL}/chat/completions` 请求;请求构造与响应解析抽成纯函数(`AIRequest.build`/`parse`)便于无网络单测。配置走 `UserDefaults`(经 `AppSettings`),prompt 以 JSON 数组存 `UserDefaults`。两个内置动作与所有自定义 prompt 复用两种「形状」(`.singleTask` / `.review`)。

**Tech Stack:** Swift / SwiftUI / SwiftData / AppKit,Swift Testing(`import Testing`),`URLSession`,`JSONSerialization`/`Codable`。`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`(纯值类型成员标 `nonisolated`)。

**重要约定(项目记忆):**
- `WorkPanel/` 与 `WorkPanelTests/` 下新增文件由 filesystem-synced group 自动纳入,**不要**改 `project.pbxproj`。
- 测试用**单套件** `-only-testing` 跑,避免整 bundle `xcodebuild test` 卡死 testmanagerd。
- 构建命令:`xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
- 单套件测试:`xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/<SuiteName>`

---

## File Structure

| 文件 | 职责 | 动作 |
|---|---|---|
| `WorkPanel/Store/AppSettings.swift` | 新增 AI 配置键与访问器 | Modify |
| `WorkPanel/AI/AIPrompt.swift` | `AIPrompt` 值类型 + `AIPromptStore`(load/save/默认种子) | Create |
| `WorkPanel/AI/AIService.swift` | `AIConfig` / `AIError` / `AIRequest`(纯函数) / `AIService` | Create |
| `WorkPanel/AI/AIContext.swift` | `renderTask` / `renderInProgress`(把任务渲染成 prompt 上下文) | Create |
| `WorkPanel/UI/AITaskExpandSheet.swift` | 单任务「梳理拓展」预览 sheet | Create |
| `WorkPanel/UI/TaskEditorView.swift` | 接入 AI 菜单 + 预览 sheet,应用结果到 `text` | Modify |
| `WorkPanel/UI/ReviewLensView.swift` | 顶部「AI 总结」卡片 | Modify |
| `WorkPanel/UI/AIPromptListView.swift` | 设置里的 prompt 列表 + 增/删/编辑器 | Create |
| `WorkPanel/UI/SettingsView.swift` | 新增「AI 助手」分组(baseURL/模型/Key + 嵌入 prompt 列表) | Modify |
| `WorkPanelTests/AISettingsTests.swift` | AI 配置访问器默认值/持久化 | Create |
| `WorkPanelTests/AIPromptTests.swift` | `AIPrompt` JSON 往返、空时返回默认 | Create |
| `WorkPanelTests/AIRequestTests.swift` | `AIRequest.build`/`parse` 纯函数 | Create |
| `WorkPanelTests/AIContextTests.swift` | `renderTask`/`renderInProgress` | Create |

---

## Task 1: AI 配置存储(AppSettings)

**Files:**
- Modify: `WorkPanel/Store/AppSettings.swift`
- Test: `WorkPanelTests/AISettingsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/AISettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct AISettingsTests {
    private func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: AppSettings.Key.aiBaseURL)
        d.removeObject(forKey: AppSettings.Key.aiModel)
        d.removeObject(forKey: AppSettings.Key.aiAPIKey)
    }

    @Test func aiConfigDefaultsToEmpty() {
        defer { clear() }
        clear()
        #expect(AppSettings.aiBaseURL.isEmpty)
        #expect(AppSettings.aiModel.isEmpty)
        #expect(AppSettings.aiAPIKey.isEmpty)
    }

    @Test func aiConfigPersistsSetValues() {
        defer { clear() }
        let d = UserDefaults.standard
        d.set("https://api.openai.com/v1", forKey: AppSettings.Key.aiBaseURL)
        d.set("gpt-4o-mini", forKey: AppSettings.Key.aiModel)
        d.set("sk-test", forKey: AppSettings.Key.aiAPIKey)
        #expect(AppSettings.aiBaseURL == "https://api.openai.com/v1")
        #expect(AppSettings.aiModel == "gpt-4o-mini")
        #expect(AppSettings.aiAPIKey == "sk-test")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AISettingsTests`
Expected: FAIL — `AppSettings.Key.aiBaseURL` / `AppSettings.aiBaseURL` 不存在,编译错误。

- [ ] **Step 3: Add keys and accessors**

In `WorkPanel/Store/AppSettings.swift`, inside `enum Key`, add after `boardHeight`:

```swift
        static let aiBaseURL = "aiBaseURL"
        static let aiModel = "aiModel"
        static let aiAPIKey = "aiAPIKey"   // 明文,与 mcpToken 一致
        static let aiPrompts = "aiPrompts" // JSON 编码的 [AIPrompt]
```

Add accessors after `boardHeight`'s computed property (before the closing `}` of `enum AppSettings`):

```swift
    static var aiBaseURL: String {
        UserDefaults.standard.string(forKey: Key.aiBaseURL) ?? ""
    }
    static var aiModel: String {
        UserDefaults.standard.string(forKey: Key.aiModel) ?? ""
    }
    static var aiAPIKey: String {
        UserDefaults.standard.string(forKey: Key.aiAPIKey) ?? ""
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AISettingsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Store/AppSettings.swift WorkPanelTests/AISettingsTests.swift
git commit -m "feat(ai): add AI config keys and accessors to AppSettings"
```

---

## Task 2: AIPrompt 模型与存储

**Files:**
- Create: `WorkPanel/AI/AIPrompt.swift`
- Test: `WorkPanelTests/AIPromptTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/AIPromptTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct AIPromptTests {
    private func clear() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.aiPrompts)
    }

    @Test func loadReturnsBuiltInDefaultsWhenEmpty() {
        defer { clear() }
        clear()
        let prompts = AIPromptStore.load()
        #expect(prompts.count == 2)
        #expect(prompts.contains { $0.shape == .singleTask })
        #expect(prompts.contains { $0.shape == .review })
    }

    @Test func saveThenLoadRoundTrips() {
        defer { clear() }
        let custom = [
            AIPrompt(id: UUID(), name: "我的拓展", shape: .singleTask, template: "AAA"),
            AIPrompt(id: UUID(), name: "我的复盘", shape: .review, template: "BBB"),
            AIPrompt(id: UUID(), name: "另一个", shape: .singleTask, template: "CCC"),
        ]
        AIPromptStore.save(custom)
        let loaded = AIPromptStore.load()
        #expect(loaded.count == 3)
        #expect(loaded[0].name == "我的拓展")
        #expect(loaded[2].template == "CCC")
        #expect(loaded[1].shape == .review)
    }

    @Test func defaultsHaveStableIDsAcrossLoads() {
        defer { clear() }
        clear()
        let a = AIPromptStore.load()
        let b = AIPromptStore.load()
        #expect(a.map(\.id) == b.map(\.id))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIPromptTests`
Expected: FAIL — `AIPrompt` / `AIPromptStore` 未定义。

- [ ] **Step 3: Implement model and store**

Create `WorkPanel/AI/AIPrompt.swift`:

```swift
import Foundation

/// 一个可命名的 AI 动作模板。`shape` 决定它跑在什么上、输出去哪:
/// - `.singleTask`:跑在单个选中任务上,预览后写入 notes。
/// - `.review`:跑在所有未完成任务上,在复盘透镜里展示。
struct AIPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var shape: Shape
    var template: String   // 作为 system message 发送

    enum Shape: String, Codable, CaseIterable, Identifiable {
        case singleTask, review
        var id: String { rawValue }
        var label: String {
            switch self {
            case .singleTask: "单任务"
            case .review:     "复盘"
            }
        }
    }
}

/// AIPrompt 的持久化:JSON 编码进 UserDefaults。空时返回两个内置默认 prompt。
enum AIPromptStore {
    /// 内置默认 prompt 用固定 UUID,保证多次 load 的 id 稳定(Picker 选中态不抖)。
    static let defaults: [AIPrompt] = [
        AIPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "梳理拓展",
            shape: .singleTask,
            template: "你是一个任务梳理助手。根据下面这条任务的标题与备注,把它梳理清楚并拓展成可执行的步骤,用 markdown 清单(可含 [ ] 复选框)输出,必要时补充关键注意事项。只输出梳理后的内容,不要寒暄。"
        ),
        AIPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "复盘总结",
            shape: .review,
            template: "你是一个工作复盘助手。下面是我所有进行中(未完成)的任务。请做一次整体复盘与总结:概述当前在推进的事情、指出重点与风险、给出接下来建议优先处理的几项。用简洁的 markdown 输出。"
        ),
    ]

    static func load() -> [AIPrompt] {
        guard let raw = UserDefaults.standard.string(forKey: AppSettings.Key.aiPrompts),
              let data = raw.data(using: .utf8),
              let prompts = try? JSONDecoder().decode([AIPrompt].self, from: data),
              !prompts.isEmpty
        else { return defaults }
        return prompts
    }

    static func save(_ prompts: [AIPrompt]) {
        guard let data = try? JSONEncoder().encode(prompts),
              let raw = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(raw, forKey: AppSettings.Key.aiPrompts)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIPromptTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/AI/AIPrompt.swift WorkPanelTests/AIPromptTests.swift
git commit -m "feat(ai): add AIPrompt model and persistence store"
```

---

## Task 3: 请求构造与响应解析(纯函数)+ AIService

**Files:**
- Create: `WorkPanel/AI/AIService.swift`
- Test: `WorkPanelTests/AIRequestTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/AIRequestTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

struct AIRequestTests {
    private let config = AIConfig(baseURL: "https://api.openai.com/v1",
                                  model: "gpt-4o-mini",
                                  apiKey: "sk-test")

    @Test func buildSetsURLMethodAndAuthHeader() throws {
        let req = try AIRequest.build(config: config, system: "S", user: "U")
        #expect(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func buildBodyHasModelAndMessages() throws {
        let req = try AIRequest.build(config: config, system: "S", user: "U")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "gpt-4o-mini")
        let messages = body?["messages"] as? [[String: String]]
        #expect(messages?.count == 2)
        #expect(messages?[0]["role"] == "system")
        #expect(messages?[0]["content"] == "S")
        #expect(messages?[1]["role"] == "user")
        #expect(messages?[1]["content"] == "U")
    }

    @Test func buildTrimsTrailingSlashOnBaseURL() throws {
        let c = AIConfig(baseURL: "https://x.test/v1/", model: "m", apiKey: "k")
        let req = try AIRequest.build(config: c, system: "S", user: "U")
        #expect(req.url?.absoluteString == "https://x.test/v1/chat/completions")
    }

    @Test func buildThrowsNotConfiguredWhenFieldBlank() {
        let c = AIConfig(baseURL: "https://x.test/v1", model: "", apiKey: "k")
        #expect(throws: AIError.notConfigured) {
            _ = try AIRequest.build(config: c, system: "S", user: "U")
        }
    }

    @Test func parseExtractsAssistantContent() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"hello world"}}]}
        """.data(using: .utf8)!
        #expect(try AIRequest.parse(data: json) == "hello world")
    }

    @Test func parseThrowsDecodeOnBadJSON() {
        let json = "{\"oops\":true}".data(using: .utf8)!
        #expect(throws: AIError.decode) {
            _ = try AIRequest.parse(data: json)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIRequestTests`
Expected: FAIL — `AIConfig` / `AIError` / `AIRequest` 未定义。

- [ ] **Step 3: Implement config, error, request, and service**

Create `WorkPanel/AI/AIService.swift`:

```swift
import Foundation

/// 出站 AI 调用所需的配置三元组(OpenAI 兼容)。
struct AIConfig: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
}

enum AIError: Error, Equatable {
    case notConfigured            // baseURL/model/apiKey 任一为空
    case network(String)          // URLSession 抛出
    case http(Int, String)        // 非 2xx,带状态码与响应体摘要
    case decode                   // 响应 JSON 无法解析出 content
}

/// 请求构造与响应解析:纯函数,无网络,便于单测。
enum AIRequest {
    nonisolated static func build(config: AIConfig, system: String, user: String) throws -> URLRequest {
        let trimmedBase = config.baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedBase.isEmpty,
              !config.model.trimmingCharacters(in: .whitespaces).isEmpty,
              !config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIError.notConfigured
        }
        let base = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        guard let url = URL(string: base + "/chat/completions") else {
            throw AIError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    nonisolated static func parse(data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw AIError.decode
        }
        return content
    }
}

/// 出站 AI 服务:读取 AppSettings 配置,发起 OpenAI 兼容请求,返回助手文本。
@MainActor
final class AIService {
    func run(systemPrompt: String, userContext: String) async throws -> String {
        let config = AIConfig(baseURL: AppSettings.aiBaseURL,
                              model: AppSettings.aiModel,
                              apiKey: AppSettings.aiAPIKey)
        let request = try AIRequest.build(config: config, system: systemPrompt, user: userContext)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIError.network("无 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, String(bodyText.prefix(200)))
        }
        return try AIRequest.parse(data: data)
    }

    /// 把 AIError 转成给用户看的简短中文提示(用于 Notice)。
    nonisolated static func message(for error: Error) -> String {
        switch error {
        case AIError.notConfigured: return "请先在设置里填写 AI 的 baseURL、模型与 API Key"
        case AIError.network(let m): return "网络错误:\(m)"
        case AIError.http(let code, _): return "请求失败(HTTP \(code))"
        case AIError.decode: return "无法解析模型返回"
        default: return "AI 调用失败"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIRequestTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/AI/AIService.swift WorkPanelTests/AIRequestTests.swift
git commit -m "feat(ai): add AIService with pure request build/parse"
```

---

## Task 4: 任务上下文渲染

**Files:**
- Create: `WorkPanel/AI/AIContext.swift`
- Test: `WorkPanelTests/AIContextTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/AIContextTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct AIContextTests {
    @Test func renderTaskIncludesTitleNotesTags() {
        let t = TodoTask(title: "写设计文档",
                         notes: "先列大纲\n再补细节",
                         priority: .high,
                         tags: ["工作", "文档"])
        let s = AIContext.renderTask(t)
        #expect(s.contains("写设计文档"))
        #expect(s.contains("先列大纲"))
        #expect(s.contains("工作"))
        #expect(s.contains("文档"))
    }

    @Test func renderInProgressListsOnlyIncompleteTasks() {
        let a = TodoTask(title: "任务A", priority: .high)
        let b = TodoTask(title: "任务B", priority: .low)
        let done = TodoTask(title: "已完成任务", priority: .medium)
        done.isCompleted = true
        let s = AIContext.renderInProgress([a, b, done])
        #expect(s.contains("任务A"))
        #expect(s.contains("任务B"))
        #expect(!s.contains("已完成任务"))
    }

    @Test func renderInProgressHandlesEmpty() {
        let s = AIContext.renderInProgress([])
        #expect(!s.isEmpty)   // 给个占位说明,而非空串
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIContextTests`
Expected: FAIL — `AIContext` 未定义。

- [ ] **Step 3: Implement rendering**

Create `WorkPanel/AI/AIContext.swift`:

```swift
import Foundation

/// 把任务渲染成喂给 LLM 的 user message 文本。
enum AIContext {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

    private static func priorityLabel(_ p: Priority) -> String {
        switch p {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }

    /// 单个任务:标题/优先级/截止/标签/备注。
    static func renderTask(_ task: TodoTask) -> String {
        var lines: [String] = []
        lines.append("标题: \(task.title)")
        lines.append("优先级: \(priorityLabel(task.priority))")
        if let d = task.deadline {
            lines.append("截止: \(dateFormatter.string(from: d))")
        }
        if !task.tags.isEmpty {
            lines.append("标签: " + task.tags.map { "#\($0)" }.joined(separator: " "))
        }
        let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("备注:")
        lines.append(notes.isEmpty ? "(无)" : notes)
        return lines.joined(separator: "\n")
    }

    /// 所有未完成任务的要点列表。
    static func renderInProgress(_ tasks: [TodoTask]) -> String {
        let pending = tasks.filter { !$0.isCompleted }
        guard !pending.isEmpty else { return "(当前没有进行中的任务)" }
        return pending.map { t in
            var line = "- [\(priorityLabel(t.priority))] \(t.title)"
            if let d = t.deadline {
                line += "(截止 \(dateFormatter.string(from: d)))"
            }
            if !t.tags.isEmpty {
                line += " " + t.tags.map { "#\($0)" }.joined(separator: " ")
            }
            return line
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIContextTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/AI/AIContext.swift WorkPanelTests/AIContextTests.swift
git commit -m "feat(ai): render task context for prompts"
```

---

## Task 5: 单任务「梳理拓展」预览 sheet

**Files:**
- Create: `WorkPanel/UI/AITaskExpandSheet.swift`

无单测(纯 UI;依据项目记忆 XCUITest 不便驱动 SwiftUI 交互)。验证靠编译 + 手动。

- [ ] **Step 1: Implement the sheet**

Create `WorkPanel/UI/AITaskExpandSheet.swift`:

```swift
import SwiftUI

/// 单任务「梳理拓展」预览:进入即调用 AI,加载时显示 spinner,成功后用 MarkdownPreview
/// 展示结果。「应用」把结果回调给调用方(由其追加到任务备注);「取消」丢弃。
struct AITaskExpandSheet: View {
    let prompt: AIPrompt
    let taskContext: String
    let onApply: (String) -> Void
    let onClose: () -> Void

    @State private var result: String = ""
    @State private var loading = true
    @State private var failed = false

    private let ai = AIService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.accentText)
                Text(prompt.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            Group {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(maxHeight: .infinity)
                } else if failed {
                    HStack { Spacer()
                        Button("重试") { run() }
                            .buttonStyle(NoirPillButtonStyle())
                        Spacer() }
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView { MarkdownPreview(text: $result).padding(8) }
                }
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.strokeStrong, lineWidth: 0.7)
            )

            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .buttonStyle(NoirPillButtonStyle())
                Button("应用到备注") { onApply(result); onClose() }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .disabled(loading || failed || result.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .onKeyPress(.escape) { onClose(); return .handled }
        .task { run() }
    }

    private func run() {
        loading = true
        failed = false
        Task {
            do {
                let text = try await ai.run(systemPrompt: prompt.template, userContext: taskContext)
                result = text
                loading = false
            } catch {
                loading = false
                failed = true
                Notice.show(AIService.message(for: error))
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add WorkPanel/UI/AITaskExpandSheet.swift
git commit -m "feat(ai): add single-task expand preview sheet"
```

---

## Task 6: 在任务编辑器接入 AI 菜单 + sheet

**Files:**
- Modify: `WorkPanel/UI/TaskEditorView.swift`

- [ ] **Step 1: Add state for the sheet**

In `TaskEditorView`, after the existing `@State private var deadline: Date?` (around line 28), add:

```swift
    @State private var expandPrompt: AIPrompt?
```

- [ ] **Step 2: Add an AI menu to the header**

In `body`, the header `HStack` currently holds the title, a `Spacer()`, and the `NoirSegmented` 编辑/预览 toggle. Insert an AI menu **before** the `NoirSegmented` (i.e. right after `Spacer()` at line ~82). The menu lists all `.singleTask` prompts;选中即触发 sheet。只有在 AI 已配置且存在单任务 prompt 时才显示:

```swift
                if !AppSettings.aiBaseURL.isEmpty {
                    let singleTaskPrompts = AIPromptStore.load().filter { $0.shape == .singleTask }
                    if !singleTaskPrompts.isEmpty {
                        Menu {
                            ForEach(singleTaskPrompts) { p in
                                Button(p.name) { expandPrompt = p }
                            }
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(resolved.fields.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
```

- [ ] **Step 3: Present the sheet and apply its result**

Add a `.sheet(item:)` modifier to the outer `VStack` of `body`. Put it right after the existing `.onChange(of: text)` modifier (around line 155):

```swift
        .sheet(item: $expandPrompt) { p in
            AITaskExpandSheet(
                prompt: p,
                taskContext: AIContext.renderTask(previewTask()),
                onApply: { appendToNotes($0) },
                onClose: { expandPrompt = nil }
            )
        }
```

- [ ] **Step 4: Add helper methods**

Add these private methods to `TaskEditorView` (e.g. just before `save()` at line ~316). `previewTask()` builds a transient `TodoTask` from the current editor fields so the AI sees unsaved edits; `appendToNotes()` appends the AI result into the editor text:

```swift
    /// 用编辑器当前内容构造一个临时任务,喂给 AI(包含尚未保存的改动)。
    private func previewTask() -> TodoTask {
        let r = resolved
        let fields = CaptureDraft.applyControls(to: r.fields,
                                                priority: priority,
                                                tags: selectedTags,
                                                deadline: deadline)
        return TodoTask(title: r.fields.title.trimmingCharacters(in: .whitespaces),
                        notes: r.notes,
                        deadline: fields.deadline,
                        priority: fields.priority,
                        tags: fields.tags)
    }

    /// 把 AI 结果作为新的一段备注追加到编辑器文本末尾。
    private func appendToNotes(_ addition: String) {
        let trimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if text.hasSuffix("\n") {
            text += "\n\(trimmed)\n"
        } else {
            text += "\n\n\(trimmed)\n"
        }
    }
```

- [ ] **Step 5: Verify it builds**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add WorkPanel/UI/TaskEditorView.swift
git commit -m "feat(ai): wire single-task expand into task editor"
```

---

## Task 7: 复盘透镜的「AI 总结」卡片

**Files:**
- Modify: `WorkPanel/UI/ReviewLensView.swift`

- [ ] **Step 1: Add state**

In `ReviewLensView`, after `@Query private var plans: [DayPlan]` (line 10), add:

```swift
    @State private var aiSummary: String = ""
    @State private var aiLoading = false
    @State private var aiPromptID: UUID?
    private let ai = AIService()
```

- [ ] **Step 2: Add the AI summary section to body**

In `body`, inside the outer `VStack(alignment: .leading, spacing: 20)`, add the AI card as the **first** child (before `section("本周 · 承诺 vs 完成")` at line 40):

```swift
                aiSection
```

- [ ] **Step 3: Implement the aiSection view and generate logic**

Add these to `ReviewLensView` (e.g. after `body`, before the existing `section(...)` helper at line 84):

```swift
    private var reviewPrompts: [AIPrompt] {
        AIPromptStore.load().filter { $0.shape == .review }
    }

    @ViewBuilder
    private var aiSection: some View {
        if !AppSettings.aiBaseURL.isEmpty, !reviewPrompts.isEmpty {
            section("AI 总结") {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { aiPromptID ?? reviewPrompts.first?.id },
                        set: { aiPromptID = $0 }
                    )) {
                        ForEach(reviewPrompts) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    .labelsHidden().fixedSize()

                    Button(aiLoading ? "生成中…" : "生成总结") { generate() }
                        .buttonStyle(NoirPillButtonStyle(prominent: true))
                        .disabled(aiLoading)
                    Spacer()
                }
                if aiLoading {
                    ProgressView().padding(.top, 4)
                } else if !aiSummary.isEmpty {
                    MarkdownPreview(text: $aiSummary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func generate() {
        let prompts = reviewPrompts
        guard let prompt = prompts.first(where: { $0.id == aiPromptID }) ?? prompts.first
        else { return }
        aiLoading = true
        Task {
            do {
                let text = try await ai.run(systemPrompt: prompt.template,
                                            userContext: AIContext.renderInProgress(tasks))
                aiSummary = text
                aiLoading = false
            } catch {
                aiLoading = false
                Notice.show(AIService.message(for: error))
            }
        }
    }
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/ReviewLensView.swift
git commit -m "feat(ai): add AI summary card to review lens"
```

---

## Task 8: prompt 列表与编辑器(设置内)

**Files:**
- Create: `WorkPanel/UI/AIPromptListView.swift`

- [ ] **Step 1: Implement the prompt list + editor**

Create `WorkPanel/UI/AIPromptListView.swift`:

```swift
import SwiftUI

/// 设置里的提示词管理:列出已保存 prompt(名字 + 形状标记),支持新增/编辑/删除。
/// 改动即时写回 AIPromptStore。
struct AIPromptListView: View {
    @State private var prompts: [AIPrompt] = AIPromptStore.load()
    @State private var editing: AIPrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prompts) { p in
                HStack(spacing: 8) {
                    Text(p.shape.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.surface, in: Capsule())
                    Text(p.name).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    Button { editing = p } label: {
                        Image(systemName: "pencil").foregroundStyle(Theme.textTertiary)
                    }.buttonStyle(.plain)
                    Button { delete(p) } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.priority(.high))
                    }.buttonStyle(.plain)
                }
                .font(.system(size: 12))
            }
            Button {
                editing = AIPrompt(id: UUID(), name: "", shape: .singleTask, template: "")
            } label: {
                Label("新增提示词", systemImage: "plus")
            }
            .buttonStyle(NoirPillButtonStyle())
        }
        .sheet(item: $editing) { p in
            AIPromptEditor(prompt: p) { saved in
                upsert(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private func upsert(_ p: AIPrompt) {
        if let i = prompts.firstIndex(where: { $0.id == p.id }) {
            prompts[i] = p
        } else {
            prompts.append(p)
        }
        AIPromptStore.save(prompts)
    }

    private func delete(_ p: AIPrompt) {
        prompts.removeAll { $0.id == p.id }
        AIPromptStore.save(prompts)
    }
}

/// 单个 prompt 的编辑表单:名字、形状、模板正文。
private struct AIPromptEditor: View {
    @State var prompt: AIPrompt
    let onSave: (AIPrompt) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.name.isEmpty ? "新增提示词" : "编辑提示词")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            TextField("名字", text: $prompt.name)
                .textFieldStyle(.roundedBorder)

            Picker("形状", selection: $prompt.shape) {
                ForEach(AIPrompt.Shape.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            TextEditor(text: $prompt.template)
                .font(.system(size: 12))
                .frame(height: 160)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.strokeStrong, lineWidth: 0.7)
                )

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .buttonStyle(NoirPillButtonStyle())
                Button("保存") { onSave(prompt) }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .disabled(prompt.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.template.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add WorkPanel/UI/AIPromptListView.swift
git commit -m "feat(ai): add prompt list and editor for settings"
```

---

## Task 9: 设置里的「AI 助手」分组

**Files:**
- Modify: `WorkPanel/UI/SettingsView.swift`

- [ ] **Step 1: Add @AppStorage bindings**

In `SettingsView`, after `@State private var mcpToken = AppSettings.mcpToken` (line 15), add:

```swift
    @AppStorage(AppSettings.Key.aiBaseURL) private var aiBaseURL = ""
    @AppStorage(AppSettings.Key.aiModel) private var aiModel = ""
    @AppStorage(AppSettings.Key.aiAPIKey) private var aiAPIKey = ""
```

- [ ] **Step 2: Add the AI 助手 section**

In `body`, add a new section **after** the existing `section("AI 接入 (MCP)", ...)` block (which ends around line 162, before the `HStack { Spacer(); Button("完成") ... }`):

```swift
            section("AI 助手", systemImage: "sparkles") {
                row("接口地址", systemImage: "link") {
                    TextField("https://api.openai.com/v1", text: $aiBaseURL)
                        .labelsHidden().frame(width: 220)
                        .multilineTextAlignment(.trailing)
                }
                divider
                row("模型名称", systemImage: "cpu") {
                    TextField("gpt-4o-mini", text: $aiModel)
                        .labelsHidden().frame(width: 220)
                        .multilineTextAlignment(.trailing)
                }
                divider
                row("API Key", systemImage: "key") {
                    SecureField("sk-…", text: $aiAPIKey)
                        .labelsHidden().frame(width: 220)
                        .multilineTextAlignment(.trailing)
                }
                divider
                VStack(alignment: .leading, spacing: 8) {
                    Label("提示词", systemImage: "text.bubble")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.textPrimary)
                    AIPromptListView()
                }
            }
```

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild -scheme WorkPanel -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full AI test suites to confirm no regressions**

Run each suite (单套件,避免整 bundle 卡死):
```bash
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AISettingsTests
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIPromptTests
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIRequestTests
xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/AIContextTests
```
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/SettingsView.swift
git commit -m "feat(ai): add AI assistant section to settings"
```

---

## Manual Verification (实机走查)

构建运行 App 后,逐项确认:

1. 设置 → 「AI 助手」:填入真实 baseURL/模型/Key;新增一个 `.singleTask` 和一个 `.review` prompt,编辑、删除均生效(重开设置仍在)。
2. 任务编辑器:标题非空时出现 ✨ 菜单,选一个单任务 prompt → 弹出 sheet → 加载 → 出结果 → 「应用到备注」把内容追加进编辑区 → 保存后任务 notes 含该内容。
3. 复盘透镜:顶部出现「AI 总结」卡片,选 prompt → 生成 → markdown 结果展示;无未完成任务时模型应被告知「没有进行中的任务」。
4. 错误路径:清空 API Key 后触发任一动作 → 底部 Notice 提示去设置填写;故意填错 baseURL → Notice 显示网络/HTTP 错误。

---

## Self-Review 结果

- **Spec 覆盖**:配置三元组(Task 1)、自定义多 prompt + 两形状(Task 2)、出站调用(Task 3)、上下文(Task 4)、单任务预览→写 notes(Task 5/6)、复盘卡片(Task 7)、设置 UI(Task 8/9)。均有对应任务。
- **占位扫描**:无 TBD/TODO,代码步骤均含完整代码。
- **类型一致**:`AIConfig`/`AIError`/`AIRequest.build`/`AIRequest.parse`/`AIService.run`/`AIService.message(for:)`/`AIPrompt`/`AIPrompt.Shape`/`AIPromptStore.load/save/defaults`/`AIContext.renderTask/renderInProgress` 在定义与调用处签名一致。
- **已知取舍**:API Key 明文存 UserDefaults;无流式;复盘结果不持久化(每次重生成);自定义 prompt 仅两种形状。
