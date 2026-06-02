# AI 助手(出站 LLM)设计

日期:2026-06-03

## 目标

为 WorkPanel 增加一个**出站**的 AI 助手能力:App 主动调用用户配置的大模型,完成两类工作:

1. **梳理拓展单个任务** —— 把某条任务的工作内容梳理、拓展,产出更细的步骤/说明。
2. **复盘总结进行中的工作** —— 对所有未完成任务做一次整体复盘与总结。

用户可自定义:

- baseURL、模型名称、API Key(OpenAI 兼容)
- 多个命名 prompt(在两个内置动作之外,还能自己加)

> 注意方向:现有的 "AI 接入 (MCP)" 是**入站**(外部 AI 客户端连进 App)。本特性是**出站**(App 调用 LLM),两者并存、互不影响。

## 关键决策(来自 brainstorming)

| 维度 | 决策 |
|---|---|
| prompt 与功能的关系 | 混合:两个内置动作 + 用户自定义 prompt |
| 复盘的"进行中"范围 | 所有未完成任务(`isCompleted == false`) |
| 梳理拓展输出 | 先预览,确认后写入该任务的 `notes` |
| 复盘输出 | 在现有「复盘」透镜里加一块 AI 总结 |
| API Key 存储 | 跟 `mcpToken` 一样走 UserDefaults(明文,已知权衡) |
| 自定义 prompt 作用域 | 复用两种内置「形状」:单任务 / 全量复盘 |
| 协议 | OpenAI 兼容 `POST {baseURL}/chat/completions` |
| 流式 | 否(v1 阻塞 + loading 态) |

## 架构

采用**最小出站 `AIService`** 方案:单个服务类构造 OpenAI 兼容请求,两个内置动作与所有自定义 prompt 都经它路由。不引入 provider 抽象层(自定义 baseURL 已覆盖所有 OpenAI 兼容端点,属 YAGNI)。

### 1. 数据与配置

`AppSettings` 新增 UserDefaults 键(沿用现有风格与类型化访问器):

- `aiBaseURL: String` —— 如 `https://api.openai.com/v1`
- `aiModel: String` —— 如 `gpt-4o-mini`
- `aiAPIKey: String` —— 明文,与 `mcpToken` 一致(权衡:UserDefaults plist 明文,非 Keychain)
- `aiPrompts: String` —— JSON 编码的 `[AIPrompt]`

`AIPrompt` 值类型(项目 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`,值类型成员需 `nonisolated`):

```swift
struct AIPrompt: Codable, Identifiable {
    let id: UUID
    var name: String
    var shape: Shape          // 决定跑在什么上、输出去哪
    var template: String      // 作为 system message 发送
    enum Shape: String, Codable { case singleTask, review }
}
```

`AIPromptStore`(或 `AppSettings` 上的静态访问器)负责数组的编解码,并在首次运行时**播种两个内置 prompt**:

- 一个 `.singleTask`「梳理拓展」
- 一个 `.review`「复盘总结」

两个内置 prompt 均可编辑/删除(删除后用户可重新新增,不做强制保留)。

### 2. `AIService`(新文件 `WorkPanel/AI/AIService.swift`)

MainActor 类,核心一个 async 方法:

```swift
func run(systemPrompt: String, userContext: String) async throws -> String
```

- 构造 `POST {baseURL}/chat/completions`,Header `Authorization: Bearer {key}`,Body `{ model, messages: [system, user], stream: false }`。
- 解析 `choices[0].message.content` 返回。
- 抛出类型化 `AIError`(配置缺失 / 网络 / HTTP 非 2xx / 解码失败),由现有 `Notice` toast 呈现。

**上下文渲染**(纯函数,可测,放在 `AIService` 或独立 helper):

- `renderTask(_:) -> String` —— 单个任务的 title/notes/deadline/priority/tags。
- `renderInProgress(_:) -> String` —— 所有 `isCompleted == false` 任务的要点列表。

**请求构造**抽成纯函数(输入 config + messages,输出 `URLRequest`),便于无网络单测,对齐现有 `HTTPMessageTests` / `MCPDispatcherTests` 的做法。

> 模板注入方式:用户 prompt 作为 system message;App 把渲染后的任务上下文作为 user message 追加。不做 `{{变量}}` 替换 —— 更简单。

### 3. 单任务流程

- `TaskEditorView` 中新增一个 "AI" 入口(列出所有 `.singleTask` prompt)。
- 选中某 prompt → 调 `AIService.run(template, renderTask(task))`。
- 弹出**预览 sheet**(markdown,复用 `MarkdownPreview`),加载时显示 spinner。
- 「应用」把结果追加到 `task.notes`(markdown,用分隔线隔开);「取消」丢弃。
- AI **不在无确认时改数据**。

### 4. 复盘流程

- `ReviewLensView` 顶部新增「AI 总结」卡片:一个 `.review` prompt 的 `Picker` + 「生成」按钮。
- 生成时调 `AIService.run(template, renderInProgress(allTasks))`,在卡片内渲染 markdown 结果。
- 结果**只读、不持久化**(每次按需重新生成),与该透镜现有的只读统计性质一致。

### 5. 设置 UI

`SettingsView` 新增「AI 助手」分组(现有「AI 接入 (MCP)」保留不动,因其为入站方向):

- 行:baseURL(TextField)、模型名称(TextField)、API Key(SecureField)。
- 提示词管理:已保存 prompt 列表(名字 + shape 标记),支持新增/编辑/删除。编辑打开小编辑器(名字、shape 分段控件、多行 template)。
- 沿用其余设置一致的 frosted-card 风格。

## 数据流

```
单任务:  TaskEditorView ──选 prompt──▶ AIService.run(template, renderTask)
                              │
                          预览 sheet ──应用──▶ task.notes 追加

复盘:    ReviewLensView ──选 .review prompt + 生成──▶ AIService.run(template, renderInProgress)
                              │
                          卡片内 markdown(不持久化)
```

## 错误处理

- 配置缺失(baseURL/model/key 任一为空):`run` 抛 `AIError.notConfigured`,UI 提示去设置里填写。
- 网络/超时:`AIError.network`,Notice 提示。
- HTTP 非 2xx:`AIError.http(status, body 摘要)`。
- 解码失败:`AIError.decode`。
- 全部经 `Notice` toast 呈现;预览 sheet / 复盘卡片在失败后回到可重试状态。

## 测试

- `AIPrompt` JSON 往返编解码;首次播种默认 prompt 的逻辑。
- `renderTask` / `renderInProgress` 纯函数输出。
- 请求构造纯函数:URL、Header、Body JSON 正确(无网络)。
- 响应解析:成功 + 各类错误形状。
- 测试中不发起真实网络请求。

## 范围与取舍(YAGNI)

明确**不做**:

- 流式输出(stream)
- provider 抽象层(OpenAI/Anthropic 多实现)
- `{{变量}}` 模板替换
- 多轮对话/历史
- 重试/退避
- 自定义 prompt 仅复用两种内置形状,不支持逐项自定义输入/输出
- 复盘结果不持久化
- API Key 不进 Keychain(明文 UserDefaults,与 `mcpToken` 一致)

## 入口默认(可改)

- 单任务触发点放在 `TaskEditorView`(而非卡片右键菜单)—— 单一清晰入口。
- 复盘结果每次重新生成、不存储。
