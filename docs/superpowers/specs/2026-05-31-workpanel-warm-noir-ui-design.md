# WorkPanel → Warm Noir Utility UI 设计

> Date: 2026-05-31 · Branch: feature/todo-app

## 目标

把 WorkPanel 现有的「浅色玻璃(`ultraThinMaterial`)」界面整体改造为 `docs/design/warm-noir-utility.md`
定义的 **Warm Noir Utility** 风格:黑底悬浮面板、克制的暖橙状态色、紧凑的系统字体布局、极少装饰。

**范围**:外壳 `BoardView` + 四个透镜(Today / Priority / Kanban / Matrix) + 共用任务卡片 `TaskCardView` / `LensCard`。

**不在本次范围**(auxiliary 窗口,Warm Noir 文档允许保持原生 macOS 风格,留作后续 pass):
`TaskEditorView`、`SettingsView`、capture 输入、`MarkdownPreview` / `MarkdownTextEditor`。

**实现策略**:Approach A —— Token 优先 + 原地重样。扩展现有 `Theme.swift` 加入 noir token 与 3-4 个轻量
modifier,再原地修改各视图样式;不重建视图层级,符合 CLAUDE.md 的「外科式修改 + 简单优先」。

## 已确认的关键决策

1. **Dark-only**:外壳强制黑色,忽略 macOS 浅色模式。Warm Noir 无浅色变体。
2. **保留多色语义**:待办应用需要颜色编码信息,故保留 优先级红/琥珀/灰、四象限蓝、标签绿、截止蓝、重复紫;
   但这些颜色只出现在 **小圆点 / 细分隔线 / 低透明 badge tint** 上。
   **橙色专门保留给交互态**:选中透镜、hover、拖拽落点、主按钮。
3. **medium 优先级 橙 → 琥珀 `#FFB340`**:避免与交互橙撞色(Warm Noir 文档允许黄色表示 medium priority)。

## 1. Theme token 层(扩展 `WorkPanel/UI/Theme.swift`)

在现有语义函数旁新增 noir token(沿用 NemoNotch `NotchTheme` 的取值,适配独立窗口):

```swift
// 表面
static let panelTop    = Color(red: 0.039, green: 0.035, blue: 0.031) // ~#0A0908 暖黑
static let panelBottom = Color(red: 0.005, green: 0.005, blue: 0.004) // ~#010101
static let surfaceSubtle   = Color.white.opacity(0.045)
static let surface         = Color.white.opacity(0.07)
static let surfaceEmphasis = Color.white.opacity(0.12)
static let surfaceWarm     = Color(red: 0.23, green: 0.11, blue: 0.035).opacity(0.64)
// 描边
static let stroke       = Color.white.opacity(0.10)
static let strokeStrong = Color.white.opacity(0.15)
static let accentStroke = accent.opacity(0.42)
// 强调
static let accent     = Color(red: 1.0, green: 0.55, blue: 0.08)
static let accentText = Color(red: 1.0, green: 0.58, blue: 0.28)
static let accentSoft = accent.opacity(0.18)
// 文字
static let textPrimary   = Color.white.opacity(0.94)
static let textSecondary = Color.white.opacity(0.62)
static let textTertiary  = Color.white.opacity(0.42)
static let textMuted     = Color.white.opacity(0.30)
```

新增轻量 modifier / helper(放在 `Theme.swift` 或新建 `NoirModifiers.swift`):

- `noirCard()` —— `surfaceSubtle` 填充 + `strokeStrong` 0.7 描边,radius `Theme.cardRadius`(8)。
- `noirColumn()` —— 安静列/象限容器:`surface` 填充 + `stroke` 0.6 描边,radius 10。
- `noirBadge(tint:)` —— capsule:font `10 bold rounded`,`tint.opacity(0.16)` 背景,`tint` 前景,h-pad 7 / v-pad 3。
- `statusDot(_ color:)` —— 语义圆点;high(红)可加微弱 glow(`color.opacity(0.5)`,radius 4)。

`promote` 规则:仅当某模式重复 ≥2 次才抽成 helper,避免过度抽象。

## 2. 语义色调校(`Theme` 内现有函数)

在 `Theme.priority` / `Theme.quadrant` / `tag` / `deadline` / `recurrence` 中替换为在近黑背景上更清晰的取值。
这些色只用于点/线/badge tint:

| 语义 | 现值 | 调校后 | 出现位置 |
|---|---|---|---|
| Priority high | red | bright red `#FF453A` | 圆点、卡片 |
| Priority medium | orange | **amber `#FFB340`** | 圆点 |
| Priority low | gray | `textTertiary` | 圆点 |
| Quadrant 重要·不紧急 | blue | bright blue `#4DA6FF` | 点 + 标题 |
| Tag | green | `#5BC16E` | `#tag` badge |
| Deadline | blue | `#4DA6FF` | badge(逾期 → 红) |
| Recurrence | purple | `#B98BFF` | 小 badge |

注:medium 改琥珀后,`Theme.quadrant(important:false, urgent:true)`(不重要·紧急)同步变琥珀。

## 3. 外壳 —— `BoardView`

- 背景:`.ultraThinMaterial` → 垂直渐变 `panelTop → panelBottom`,裹在 `RoundedRectangle(cornerRadius: Theme.panelRadius)`(14)
  内;叠加 `stroke`(白 8%)描边;外加 shell 阴影(黑 0.34,radius 14)。
- Header 布局:`看板` 18-bold `textPrimary` + 计数 badge(左)· **透镜 tab 条**(中)· 齿轮 + `esc` 提示(右)。
  - 计数 `N 项` 用 `textTertiary`;齿轮 `textTertiary`,hover → `textPrimary`;`esc 收起` `textMuted` 11。
- `Divider()` → 一条 `stroke` 细线(`Rectangle().fill(Theme.stroke).frame(height: 1)`)。
- **透镜 tab 条替换 segmented `Picker`**:capsule 分组控件。背景 `surfaceSubtle` capsule;每段 = SF Symbol + 短标签
  (今日 `calendar` / 优先级 `flag` / 看板 `rectangle.split.3x1` / 矩阵 `square.grid.2x2`)。
  选中段 = `surfaceEmphasis` 填充 + `textPrimary`;未选 = `textTertiary` + 透明。选中切换用 tab-switch spring
  (`.spring(duration: 0.28, bounce: 0.06)`,可用 `matchedGeometryEffect` 平滑移动高亮)。

## 4. 任务卡片 —— `TaskCardView`

- 容器背景 `controlBackgroundColor` → `.noirCard()`。
- 完成圆圈按钮:`textTertiary`,hover → `accent`。
- 优先级圆点:`statusDot(Theme.priority(task.priority))`,7px;high 带微弱 glow。
- 标题:13 `textPrimary`,`lineLimit(2)`。
- meta 行从「彩色纯文本」改为 **capsule badge**:
  - 截止:`noirBadge`,逾期 → 红 tint(`d < .now`),否则 deadline 蓝 tint;文案保持短时间格式。
  - 重复:`noirBadge` 紫 tint,带 `repeat` SF Symbol + `Theme.recurrenceLabel`。
  - 标签:每个 `#tag` 一个绿 tint `noirBadge`。
- `trailing` 槽不变(行为由调用方注入)。

## 5. 列与象限

### Priority / Kanban 列(`PriorityLensView` / `KanbanLensView`）
- 容器 `Color.primary.opacity(0.05)` → `.noirColumn()`。
- 列头:语义圆点(priority 列)/ 列名 + 13-bold `textPrimary` + 计数 badge。
- `+ 添加任务` / 新建列文案 → `accentText` 文字动作。Kanban 的 `plus` / `ellipsis` 按钮 → `textTertiary`。
- 归档列:保留绿色 `checkmark.circle.fill`(success 语义)+ `textMuted` 删除线标题。

### 拖拽落点高亮(可选,需小改 `DeferredDrop.swift`)
- `deferredDrop` 当前用 `dropDestination(for:action:)`,**不暴露 `isTargeted`**。
- 若要落点高亮(列在卡片悬停时显示 `accentStroke` + 淡 `surfaceWarm`),需把 `deferredDrop` 扩展为使用
  `dropDestination(for:action:isTargeted:)` 重载并新增一个 `isTargeted` binding 参数。
- 列为 **可选增强**,优先级低;若为保持外科式修改而跳过,行为不变。实现时再定。

### Matrix 象限(`MatrixLensView`）
- 容器 → `.noirColumn()`。
- 保留语义象限色于「点 + 标题 + 细分隔线」(`color.opacity(~0.45)`)。
- 动作标签(`马上做` 等)→ `textTertiary`;空态 `空` → `textMuted`。

## 6. Today 透镜 + 滚动渐变

- 卡片走 noir 样式;`maxWidth: 560` 内容上限保留。
- **`ScrollEdgeFade.swift`**:当前渐变带用 `.ultraThinMaterial`。改为可传入 fade 色,默认 `Theme.panelBottom`
  实色(或暖色 `scrollFade`),使其淡入外壳黑底而非半透材质。给 `scrollEdgeFade(height:)` 加可选
  `fade: Color = Theme.panelBottom` 参数,band 的 `.fill` 改用该色。
- 空态:`今日无到期任务` 配一个 SF Symbol(如 `checkmark.seal`)`textSecondary`,去掉 🎉(noir 文案纪律)。

## 7. 验证标准

- [ ] App 在 macOS 浅色 / 深色模式下外壳都呈黑底(dark-only)。
- [ ] 四个透镜 + 卡片均使用 `Theme` noir token,无遗留 `ultraThinMaterial` / `controlBackgroundColor` /
      `Color.primary.opacity(...)` 容器底。
- [ ] 橙色只出现在交互态(选中透镜 / hover / 主按钮 / 落点);数据语义色只在点/线/badge。
- [ ] medium 优先级显示琥珀,不与交互橙混淆。
- [ ] badge 为 capsule、`10 bold rounded`、正确 padding;逾期 badge 显红。
- [ ] 透镜切换用 spring 动画,无布局跳动;hover 不引起布局位移。
- [ ] 长标题 / 标签 truncate,不挤出控件;计数与时间在稳定槽位。
- [ ] 滚动边缘渐变淡入外壳黑底。
- [ ] 对照 `docs/design/ui-review-checklist.md` 的 Anti-Slop Gate 全部通过。
- [ ] 现有单元测试(BoardStore / TodoStore 等)与 per-suite UI smoke 仍通过(注意:全 bundle `xcodebuild test`
      可能 wedge testmanagerd,用 `-only-testing` 分套验证)。

## 受影响文件清单

| 文件 | 改动 |
|---|---|
| `WorkPanel/UI/Theme.swift` | 新增 noir token + 调校语义色 |
| `WorkPanel/UI/NoirModifiers.swift`(新建,或并入 Theme) | `noirCard` / `noirColumn` / `noirBadge` / `statusDot` |
| `WorkPanel/UI/BoardView.swift` | 外壳背景、header、透镜 tab 条 |
| `WorkPanel/UI/TaskCardView.swift` | 卡片容器 + badge 化 meta |
| `WorkPanel/UI/TodayLensView.swift` | noir 卡片 + 空态 |
| `WorkPanel/UI/PriorityLensView.swift` | noir 列 |
| `WorkPanel/UI/KanbanLensView.swift` | noir 列 + 归档 + 按钮色 |
| `WorkPanel/UI/MatrixLensView.swift` | noir 象限 + 语义色标题 |
| `WorkPanel/UI/ScrollEdgeFade.swift` | 渐变带 fade 色参数 |
| `WorkPanel/UI/DeferredDrop.swift` | (可选)`isTargeted` 落点高亮 |
