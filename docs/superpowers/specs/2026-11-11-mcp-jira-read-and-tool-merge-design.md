# MCP: Jira 读取 + 工具面收敛 — 设计

日期:2026-11-11 · 状态:已批准(对话中拍板)

## 意图

MCP 调用方(AI 侧)目前看不到 Jira 来源的任务,工具面又有三个语义重复/无用的动词(`complete_task`、`reopen_task` 可由 `update_task` 表达,`snooze_task` 无人用)。一次收敛:加一个 Jira 读工具,合并状态转换,删掉 snooze。

## 现状

- `TodoTask.jiraKey: String?` / `jiraSyncedAt: Date?` 标记 Jira 来源([TodoTask.swift:23](../../../WorkPanel/Models/TodoTask.swift))。
- `TaskDTO` 不暴露这两个字段。
- MCP 工具 10 个;`TodoStore.complete` 完成循环任务时插入并返回下一次出现。

## 设计

1. **`list_jira_tasks`(新读工具)**:返回所有 `jiraKey != nil` 的任务;可选 `completed: boolean` 过滤,默认全量。
2. **`TaskDTO` 增加可选字段** `jiraKey: String?`、`jiraSyncedAt: String?`(ISO-8601,非 Jira 任务为 null)——所有读工具都能看出 Jira 来源。
3. **`complete_task` / `reopen_task` 并入 `update_task`**:
   - `update_task` 增加可选 `completed: boolean`;true → 走 `todo.complete`(循环任务产生 next,false → 走 `todo.reopen`。
   - 返回形状统一为 `{"task": TaskDTO, "next": TaskDTO?}`(`CompleteResult` 更名 `UpdateResult`);next 仅在本次调用完成了一个循环任务时非空。
   - 完成路径取消本任务提醒、为 next 重新排提醒;reopen 随 update 通用尾部取消+重排(与现有 update_task 字段更新一致)。
4. **删除 `snooze_task` 工具**(路由、目录、测试);`TodoStore.snooze` 与 `TaskDTO.snoozedUntil` 保留(UI 仍用 snooze)。

收敛后工具面(8 个):`list_tasks`、`get_task`、`list_columns`、`list_jira_tasks`、`create_task`、`update_task`、`delete_task`、`move_task`。

## 非目标

- 不触发 Jira 拉取、不回写 Jira(纯读本地已同步数据)。
- `create_task` 不支持出生即完成。

## 已拍板的取舍

- `update_task` 返回形状变化(裸 TaskDTO → `{task, next}`)是破坏性变更,调用方是用户自己的 AI 集成,接受。
- 已完成任务再次 `completed: true` 不重复产生 next(幂等守卫:`completed` 仅在与当前 `isCompleted` 不同时生效)。
