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
- [ ] 写周报 !高 #工作
    汇总本周进展
    @张三 要数据
- [ ] 买菜

## 开发中
- [ ] 修复登录bug !高

## 未分类
- [ ] 随手记一条
```

规则:

- **条目首行** = 标题 + **仅** `!优先级`(`!高`/`!中`/`!低`)与 `#标签`(`#x`)两类 token。token 写在标题之后(title-first,便于阅读;解析与顺序无关)。
- **时间不纳入本编辑器。** 截止时间、开始日期、重复、紧急 等无法用 token 无损往返的字段**不显示、不解析、保存时原样保留**(靠身份)。要改这些去单任务编辑器(⌘⌥J,有日历控件)。因此本视图不复用 `InputParser`/`CaptureDraft`(它们会把「明天/18:00/每周一」当时间吃掉);改用一个只认 `!优先级`/`#标签` 的轻量行解析器 `WorkLine`——其余文字(含「明天」等)一律当作标题字面量保留。
- **「缺省即保留」语义**(对已匹配的现有任务):行内无 `!` token → 保留原优先级;行内无 `#标签` → 保留原标签;有则替换。
- **缩进子行**(条目下方的缩进行)= 该任务的 `notes`,保存时剥除缩进、用换行拼接。
- **复选框:** 条目渲染为 `- [ ]`。额外行为:若用户勾成 `- [x]` 并保存,则该任务被标记完成(`isCompleted = true`,`completedAt = now`),下次打开不再出现。
- **空标题行**(`- [ ]` 后无标题文字):新行 → 不创建;已匹配的现有任务行被清空标题 → 视为删除(行已无内容)。
- **标题(`## …`)是只读结构。** 把条目移到另一个标题下 → 改该任务的 `columnID`;编辑标题文字不是受支持的「重命名/新建列」方式。标题文字按名称匹配现有列;无法匹配的标题,其下条目落入未分类(`columnID = nil`)。

## 身份识别与保存(方案 A:实时 range 跟踪)

身份用**锚点(anchor)**实现,不写入可见文本、不依赖 NSTextStorage 自定义属性(故与编辑器实现无关):
- **锚点** = 每个任务条目「`- ` 行起始」的字符偏移(Character 索引)。`serialize` 生成文本时连同初始锚点数组 `[(id, offset)]` 一并返回。
- 编辑期间靠 SwiftUI `onChange(of: text)` 拿到 (旧串, 新串),纯函数算出单段编辑 `(loc, oldLen, newLen)`(公共前缀/后缀长度法),再纯函数平移每个锚点:`offset ≥ loc+oldLen` → 加 `newLen-oldLen`;`offset ≤ loc` → 不动;落在删除区间内 → 溶解(丢弃)。文本视图每次变更只产生一段连续替换,故单段假设成立。

**⌘↩ 保存** 时:把当前文本按行解析成块(标题行 / `- [ ]` 条目行 + 其缩进子行),每块记其条目行起始偏移;块偏移**精确等于**某存活锚点 → 该任务 id,否则 → 新任务。对账成变更集:

| 文档侧 | 动作 |
|---|---|
| 块偏移命中锚点 | **更新**:标题 / notes / 优先级(缺省保留)/ 标签(缺省保留)+ 列(来自其标题)+ `boardOrder`(文档顺序);`[x]` → 标记完成。**时间类字段一律不动。** |
| 块无锚点 | **新建**到其标题对应的列(优先级取 `!` token 否则默认,标签取 `#`,无时间) |
| 锚点无命中块 | **删除**(`ReminderScheduler.cancel` + `TodoStore.delete`,不二次确认) |
| 合并两条目为一行 | 第二个块的起始偏移落入删除区间 → 其锚点溶解 → 对应任务被删除;首块锚点不动,保留身份 |
| 拆分一条目为两行 | 原锚点不动留在第一行;新行起始偏移不命中任何锚点 → 新建 |
| 空标题行 | 新行不创建;现有任务行被清空标题 → 不在解析块中 → 其锚点无命中 → 删除 |

**误删防护:** 删除集 = (打开文档时存在的 id 集) − (保存时仍存活的 id 集)。编辑器打开期间经 MCP/同步外部新建的任务,其 id 从未被跟踪,因此永不被删——只是本次不显示,下次打开才出现。

**应用方式:** 复刻 `TaskEditorView.save()` 的写法——经 `TodoStore` / `BoardStore.setColumn` / `TagStore`(含标签注册)落库,逐任务 `ReminderScheduler.schedule`,最后一次 `context.saveTracking()`,再关闭面板。**esc** 丢弃全部改动直接关闭。

## 组件划分

- **`WorkLine`**(纯函数、`nonisolated`):`parse(_:) -> (title, priority: Priority?, tags: [String])`,只认 `!优先级`/`#标签`,其余为标题字面量。
- **`WorkDocument`**(纯函数、`nonisolated`),不依赖 UI / SwiftData,像 `BoardStore`/`Reorder` 一样纯单测:
  - `serialize(columns:tasks:) -> (text: String, anchors: [Anchor])`(`Anchor = (id: UUID, offset: Int)`)
  - `parse(text:columns:) -> [Block]`(Block:列、标题、priority?、tags、notes、条目行起始偏移)
  - `computeEdit(old:new:) -> Edit` 与 `shift(anchors:by:) -> [Anchor]`(锚点平移)
  - `reconcile(blocks:anchors:liveTasks:) -> ChangeSet`(creates / updates / deletes),`liveTasks` 为值快照(id+现有 priority/tags 供「缺省保留」判定)
- **`WorkDocApplier`**(`@MainActor`):把 `ChangeSet` 落到 `ModelContext`——经 `TodoStore`/`BoardStore.setColumn`/`TagStore`(含标签注册)/`ReminderScheduler`,逐任务后一次 `saveTracking()`。可用内存 `ModelContainer` 测。
- **`AllTasksEditorView`**:SwiftUI 外壳,持有 `text` 与 `anchors` 状态,`onChange(of: text)` 调 `shift`,复用 `NativeTextViewWrapper` + 共享 `markdownConfig`。
- **`PanelController`** 复用(加可配置 `frameAutosaveName`)+ `HotkeyManager`/`AppDelegate` 快捷键接线。

## 错误与边界处理

- 空标题条目 → 跳过,不阻塞整次保存。
- 无法匹配列名的标题 → 其下条目落入未分类。
- 外部并发改动(MCP/同步)→ 见上「误删防护」,按 id 对账,外部新建不受影响。
- 任务量为典型规模,单缓冲区性能无虞。

## 测试

风险集中在纯函数层,以单元测试覆盖(XCUITest 无法驱动 markdown 文本编辑,故行为不靠 UI 测试):

- **`WorkLine.parse`:** 取 `!优先级`/`#标签`;「明天」等留在标题;无 token 时 priority=nil。
- **serialize:** 分组与排序、`## 未分类`、notes 缩进、排除已完成、title-first token、anchor 偏移正确。
- **computeEdit / shift:** 编辑在锚点后(平移)、前(不动)、标题内(锚点不动)、整行删除(溶解)、合并(次块溶解)、拆分(原锚点不动)、边界插入。
- **parse + reconcile:** create / update(缺省保留 priority/tags)/ delete;移动列;空标题(新行跳过、现有清空→删);外部新建任务的误删防护;`boardOrder` 重排;`[x]` → 完成。
- **`WorkDocApplier`**(内存 `ModelContainer`):落库后任务字段、列、标签注册、删除 + Tombstone 正确。

外加一个 smoke UI 测试:⌘⌥L 打开面板可达。

## 复用的既有件

`Priority`(优先级)、`TaskEditorView.markdownConfig`(着色,抽为共享)、`NativeTextViewWrapper`、`TodoStore` / `BoardStore` / `TagStore` / `ReminderScheduler`(落库与提醒)、`PanelController` / `KeyablePanel`、`HotkeyManager` + `AppDelegate` 接线。不复用 `InputParser`/`CaptureDraft`(见格式一节)。
