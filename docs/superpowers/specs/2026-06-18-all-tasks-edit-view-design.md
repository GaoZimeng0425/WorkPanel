# 全量工作内容编辑器(All-Tasks Edit View)

**日期:** 2026-06-18
**状态:** 设计已确认,待写实现计划

## 目标

一个全局快捷键,打开一份把**所有未完成任务**渲染成的 Markdown 文档。用户在这一个文本面板里快速修改所有任务、移动状态、新增任务,⌘↩ 一次性保存全部改动。沿用 App 既有的「文本优先 / 第一行 token 语法」哲学,与单任务捕获编辑器(⌘⌥J)一脉相承。

## 非目标

- 不在此视图里新建 / 重命名 / 重排「列(状态)」——标题是只读结构。
- 不展示已完成任务。
- 不做所见即所得(WYSIWYG)——沿用编辑器的原始 markdown + 实时着色,不隐藏标记。
- 不替代单任务编辑器(⌘⌥J)或看板(⌘⌥K),是三者并列的第三个入口。

## 入口与外壳

- **快捷键:** 新增 `KeyboardShortcuts.Name.toggleAllEdit`,默认 **⌘⌥L**(J=capture、K=board、L=list-all)。在 `HotkeyManager` 增加 `registerAllEdit(_:)`,在 `AppDelegate.applicationDidFinishLaunching` 像现有两个一样注册,`toggleAllEdit()` 切换面板显隐。
- **面板:** **复用现有 `PanelController`**(无需新建面板控制器)——它本就内容无关:`show(_:)` 接受任意 `@ViewBuilder`,自带无边框/居中/可缩放(560×580,上限 900×1100)/ esc 取消 / 记忆位置 / 自动聚焦文本域。唯一改动:把当前写死的 `frameAutosaveName`("WorkPanelTaskEditorFrame")改成 `init` 参数;在 `AppDelegate` 里再实例化一个 `PanelController(frameAutosaveName: "WorkPanelAllEditFrame")`,使全量编辑器记住自己独立、更大的尺寸。Esc 走面板层 `onCancel` → 丢弃并关闭;再次按快捷键若可见则隐藏。
- **视图:** 新增 `AllTasksEditorView`(SwiftUI):顶部标题栏、中部一个铺满的 `NativeTextViewWrapper`、底部 `⌘↩ 保存 / esc 取消` 页脚。**不复用 `TaskEditorView`**——后者整个围绕单个任务构建(单任务 `@State`、per-task 控件、单任务 `save()`),与「一个缓冲区代表多条任务」的形态相悖。复用的粒度是 markdown 编辑器零件:`NativeTextViewWrapper` + 把 `TaskEditorView.markdownConfig` 抽成共享配置,两视图共用同一套着色。

## 文档格式

打开时把所有 `isCompleted == false` 的任务序列化成一份 markdown,按列(`BoardColumn.order`)分组;末尾追加 `## 未分类` 收纳 `columnID == nil` 的未完成任务(仅当存在时):

```
## 计划中
- [ ] 明天 18:00 !高 #工作 写周报
    汇总本周进展
    @张三 要数据
- [ ] 买菜

## 开发中
- [ ] 下周一 修复登录bug

## 未分类
- [ ] 随手记一条
```

规则:

- **条目首行** = 标题 + 与捕获编辑器第一行相同的自然语言 token 语法(经 `InputParser` / `CaptureDraft.resolve`):截止时间 / `!优先级` / `#标签` / 重复 / 紧急。
- **缩进子行**(条目下方的缩进行)= 该任务的 `notes`,保存时剥除缩进、用换行拼接。
- **复选框:** 条目渲染为 `- [ ]`。额外行为:若用户勾成 `- [x]` 并保存,则该任务被标记完成(`isCompleted = true`,`completedAt = now`),下次打开不再出现。
- **标题(`## …`)是只读结构。** 把条目移到另一个标题下 → 改该任务的 `columnID`;编辑标题文字不是受支持的「重命名/新建列」方式。标题文字按名称匹配现有列;无法匹配的标题,其下条目落入未分类(`columnID = nil`)。
- `startDate`(开始时间)无法用 token 表达,文档中不出现,靠身份保留(见下)。

## 身份识别与保存(方案 A:实时 range 跟踪)

文档生成时给每个**任务块**(首行 + 其缩进子行)附带一个不可见身份;随用户编辑实时维持(经 `NSTextStorage` 编辑跟踪 / 自定义身份属性——以能在 markdown 着色重排后存活者为准,实现期验证;若引擎会清掉自定义属性,则退回手工 range 偏移跟踪)。

**⌘↩ 保存** 时,把文档与**当前存活**任务对账成一个变更集:

| 文档侧 | 动作 |
|---|---|
| 块仍存活(即便大改) | **更新**:标题/notes/截止/优先级/标签/重复/紧急 + 列(来自其标题)+ `boardOrder`(来自文档顺序) |
| 新块(无身份) | **新建**到其标题对应的列 |
| 被删去的块 | **删除**(`ReminderScheduler.cancel` + `TodoStore.delete`,不二次确认) |
| 合并两条目为一行 | 合并后的行保留**第一个**块的身份,第二个块对应的任务被删除 |
| 拆分一条目为两行 | 原身份留在第一行,新行新建任务 |
| 空标题条目(`- [ ]` 后无内容) | 静默跳过,不创建 |

**误删防护:** 删除集 = (打开文档时存在的 id 集) − (保存时仍存活的 id 集)。编辑器打开期间经 MCP/同步外部新建的任务,其 id 从未被跟踪,因此永不被删——只是本次不显示,下次打开才出现。

**应用方式:** 复刻 `TaskEditorView.save()` 的写法——经 `TodoStore` / `BoardStore.setColumn` / `TagStore`(含标签注册)落库,逐任务 `ReminderScheduler.schedule`,最后一次 `context.saveTracking()`,再关闭面板。**esc** 丢弃全部改动直接关闭。

## 组件划分

- **`WorkDocument`**(纯函数、`nonisolated`):
  - `serialize(columns:tasks:) -> (text: String, idMap: [UUID: 标记])`
  - `reconcile(text:idMap:liveTasks:columns:) -> ChangeSet`(creates / updates / moves / deletes)
  - 不依赖 UI、不依赖 SwiftData 实体的可变状态,可像 `BoardStore` / `Reorder` 一样纯单测。
- **身份跟踪器**:编辑期间维持「块 ↔ id」。
- **`AllTasksEditorView`**:SwiftUI 外壳,复用 `NativeTextViewWrapper` + 共享 `markdownConfig`。
- **`PanelController`** 复用(加可配置 `frameAutosaveName`)+ `HotkeyManager`/`AppDelegate` 快捷键接线。

## 错误与边界处理

- 空标题条目 → 跳过,不阻塞整次保存。
- 无法匹配列名的标题 → 其下条目落入未分类。
- 外部并发改动(MCP/同步)→ 见上「误删防护」,按 id 对账,外部新建不受影响。
- 任务量为典型规模,单缓冲区性能无虞。

## 测试

风险集中在 `WorkDocument`,以单元测试覆盖(XCUITest 无法驱动 markdown 文本编辑,故行为不靠 UI 测试):

- **serialize:** 分组与排序、`## 未分类`、notes 缩进、排除已完成。
- **reconcile:** create / update / move / delete / merge / split;空标题跳过;外部新建任务的误删防护;`boardOrder` 重排;标签注册;`[x]` → 完成。

外加一个 smoke UI 测试:⌘⌥L 打开面板可达。

## 复用的既有件

`InputParser` / `CaptureDraft`(token 解析)、`TaskEditorView.markdownConfig`(着色)、`TodoStore` / `BoardStore` / `TagStore` / `ReminderScheduler`(落库与提醒)、`KeyablePanel` 及面板控制器模式、`HotkeyManager` + `AppDelegate` 接线。
