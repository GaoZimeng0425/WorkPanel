# Plan: MCP 工具 `pull_jira`(触发 Jira 拉取)

日期:2026-11-19 · 状态:已拍板待实现 · 裁决来源:用户(AskUserQuestion)

## 需求

MCP 客户端(AI 代理)可主动触发一次 Jira 拉取,与看板按钮/定时器同入口,实现"拉取 → 读列 → 挪卡"闭环。

## 设计定稿

- 工具名 `pull_jira`,无参数。
- 入口唯一:走 `JiraPullRunner.pullNow`(防重入、日志、通知全部共用);为此给 `pullNow` 加 `fetcher: (any JiraFetching)? = nil` 注入参数(生产 nil → 真 JiraClient,测试注入脚本化 fake)。
- **noticeOnSuccess: true**(用户拍板:与手动按钮一致,成功弹 Notice 横幅;NemoNotch 有新增时照常弹卡)。
- 返回 `PullJiraResult`(Codable):
  - 成功:`{pulled: true, inserted, insertedTitles: ["[KEY] 标题"...], updated, completed, skipped, truncated, failedMessage}`(**带明细**,用户拍板;failedMessage 在写入存储失败等场景非空)
  - 未配置:`{pulled: false, reason: "Jira not configured"}`
  - 防重入:`{pulled: false, reason: "a pull is already running"}`(handler 先查 jiraConfigured,nil 返回即归因 already running)

## 改动面

1. `WorkPanel/Sync/Jira/JiraPullService.swift` — `JiraPullRunner.pullNow` 加 fetcher 参数(默认 nil)
2. `WorkPanel/MCP/MCPToolHandlers.swift` — init 加 `jiraFetcher`;call 加 case;`pullJira()` + `PullJiraResult`
3. `WorkPanel/MCP/MCPDispatcher.swift` — tools 列表加 `pull_jira` 条目
4. `WorkPanelTests/MCPToolHandlersTests.swift` — makeHandlers 加注入参数;两个用例(未配置 → reason;注入 fetcher → pulled + 计数 + 明细 + 落库)

## 已知副作用(接受)

测试走真 `pullNow(noticeOnSuccess: true)` 会在测试宿主闪现一个 Notice 面板(1.8s 自动消失,不抢 key、忽略鼠标),不影响其他并行用例——不值得为此给 Notice 加注入点。

## 验收

- 新用例红→绿;全量 WorkPanelTests 过;部署后 MCP tools/list 出现第 9 个工具。
