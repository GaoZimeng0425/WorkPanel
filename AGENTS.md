# AGENTS.md

## 1. Think Before Coding
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.

## 2. Simplicity First
- Minimum code that solves the problem. No features, abstractions, or configurability beyond what was asked.
- If a senior engineer would say it's overcomplicated, simplify.

## 3. Surgical Changes
- Touch only what you must. Don't "improve" adjacent code, comments, or formatting; match existing style.
- Clean up only what your own changes orphaned; unrelated dead code gets mentioned, not deleted.
- Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution
- Turn tasks into verifiable goals ("write a failing test, then make it pass"); loop until verified.
- For multi-step tasks, state a brief plan with a verify check per step.

---

# 项目工作流约定(必读)

## Superpowers 流程是强制的

任何功能开发或 bug 修复都必须走仓库内置的 superpowers 流程(技能在 `.zcode/skills/`,入口见 using-superpowers:开始任何动作前先查技能,有 1% 可能适用就必须调用):

- 新功能:brainstorming(澄清需求/产出 spec)→ writing-plans 把实现计划落到 `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` → 用 executing-plans(Native;接口已钉死的小功能优先)或 subagent-driven-development 逐任务实现,全程 TDD(红→绿→提交)。
- 修 bug:先 systematic-debugging 定位根因,再写复现测试后修复。
- spec 可以由用户提供的契约/接口文档充当;执行中的裁决记入台账 `.superpowers/sdd/<plan>/progress.md`,不许悄悄偏离计划。

## 禁止 e2e/UI 测试

- 不运行、不新增任何会拉起 app 的 e2e/UI 测试(WorkPanelUITests、BoardUITests 等):它们会反复启动应用、切换外观,打扰正在用电脑的用户。
- 所有测试门槛(逐任务与收尾全量)只跑单元包:
  `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests CODE_SIGNING_ALLOWED=NO`
- UI 测试失败不构成回归阻塞;端到端验证交给用户手动确认。
