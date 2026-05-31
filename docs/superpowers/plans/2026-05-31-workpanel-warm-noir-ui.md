# WorkPanel Warm Noir Utility UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle WorkPanel's board shell, four lenses, and shared task card from the current light `ultraThinMaterial` look to the black-on-warm-orange Warm Noir Utility style.

**Architecture:** Token-first, in-place restyle (brainstorm Approach A). Extend `Theme.swift` with a noir token set + tuned semantic colors, add a small `NoirModifiers.swift` (card/column/badge/dot helpers), then restyle each existing view in place. No view-hierarchy rebuild. Spec: `docs/superpowers/specs/2026-05-31-workpanel-warm-noir-ui-design.md`.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`import Testing`), Xcode project `WorkPanel.xcodeproj` (scheme `WorkPanel`).

**Verification note:** This is a pure visual restyle — SwiftUI styling is not red-green unit-testable. Except Task 1 (which changes `Theme.priority` values covered by `ThemeTests`), each task is verified by **build success + a visual check**. Existing unit suites are run per-`-only-testing` at the end (full-bundle `xcodebuild test` can wedge `testmanagerd` — never run the whole bundle).

**Standard build command** (used as "Run:" in most steps):
```bash
xcodebuild -project WorkPanel.xcodeproj -scheme WorkPanel -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected on success: `** BUILD SUCCEEDED **`

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `WorkPanel/UI/Theme.swift` | Noir color/surface/text tokens + tuned semantic colors | Modify |
| `WorkPanel/UI/NoirModifiers.swift` | `noirCard()`, `noirColumn()`, `noirBadge(_:)`, `StatusDot` | Create |
| `WorkPanel/UI/TaskCardView.swift` | Card: noir surface + status dot + capsule badges | Modify |
| `WorkPanel/UI/BoardView.swift` | Black shell, noir header, lens tab strip, dark-only | Modify |
| `WorkPanel/UI/PriorityLensView.swift` | Noir columns | Modify |
| `WorkPanel/UI/KanbanLensView.swift` | Noir columns + archive + button colors | Modify |
| `WorkPanel/UI/MatrixLensView.swift` | Noir quadrants, semantic-colored titles | Modify |
| `WorkPanel/UI/TodayLensView.swift` | Noir cards + empty state | Modify |
| `WorkPanel/UI/ScrollEdgeFade.swift` | Fade band into shell black (color param) | Modify |
| `WorkPanel/UI/DeferredDrop.swift` | (Optional) `isTargeted` for drop highlight | Modify |
| `WorkPanelTests/ThemeTests.swift` | Update priority-color assertions | Modify |

---

## Task 1: Noir tokens + tuned semantic colors

**Files:**
- Modify: `WorkPanel/UI/Theme.swift`
- Test: `WorkPanelTests/ThemeTests.swift`

- [ ] **Step 1: Update the failing test to expect the new priority colors**

Replace the `priorityColors()` test in `WorkPanelTests/ThemeTests.swift`:

```swift
    @Test func priorityColors() {
        #expect(Theme.priority(.high)   == Color(red: 1.0, green: 0.27, blue: 0.23))
        #expect(Theme.priority(.medium) == Color(red: 1.0, green: 0.70, blue: 0.25))
        #expect(Theme.priority(.low)    == Color.white.opacity(0.42))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ThemeTests 2>&1 | tail -15
```
Expected: FAIL on `priorityColors()` (Theme still returns `.red`/`.orange`/`.gray`).

- [ ] **Step 3: Add noir tokens and tune semantic colors in `Theme.swift`**

Add these `nonisolated static let` tokens inside `enum Theme` (nonisolated so the existing `nonisolated` semantic funcs can reference them):

```swift
    // MARK: Noir 表面/描边/强调/文字 token
    nonisolated static let panelTop      = Color(red: 0.039, green: 0.035, blue: 0.031)
    nonisolated static let panelBottom   = Color(red: 0.005, green: 0.005, blue: 0.004)
    nonisolated static let surfaceSubtle   = Color.white.opacity(0.045)
    nonisolated static let surface         = Color.white.opacity(0.07)
    nonisolated static let surfaceEmphasis = Color.white.opacity(0.12)
    nonisolated static let surfaceWarm     = Color(red: 0.23, green: 0.11, blue: 0.035).opacity(0.64)
    nonisolated static let stroke       = Color.white.opacity(0.10)
    nonisolated static let strokeStrong = Color.white.opacity(0.15)
    nonisolated static let accent     = Color(red: 1.0, green: 0.55, blue: 0.08)
    nonisolated static let accentText = Color(red: 1.0, green: 0.58, blue: 0.28)
    nonisolated static let accentSoft = accent.opacity(0.18)
    nonisolated static let accentStroke = accent.opacity(0.42)
    nonisolated static let textPrimary   = Color.white.opacity(0.94)
    nonisolated static let textSecondary = Color.white.opacity(0.62)
    nonisolated static let textTertiary  = Color.white.opacity(0.42)
    nonisolated static let textMuted     = Color.white.opacity(0.30)
```

Replace the existing `priority`, `quadrant`, `tag`, `deadline`, `recurrence` declarations with:

```swift
    nonisolated static func priority(_ p: Priority) -> Color {
        switch p {
        case .high:   Color(red: 1.0, green: 0.27, blue: 0.23) // #FF453A
        case .medium: Color(red: 1.0, green: 0.70, blue: 0.25) // #FFB340 琥珀,避让交互橙
        case .low:    textTertiary
        }
    }
    nonisolated static func quadrant(important: Bool, urgent: Bool) -> Color {
        switch (important, urgent) {
        case (true, true):   priority(.high)
        case (true, false):  Color(red: 0.30, green: 0.65, blue: 1.0) // #4DA6FF
        case (false, true):  priority(.medium)
        case (false, false): priority(.low)
        }
    }
    nonisolated static let tag        = Color(red: 0.36, green: 0.76, blue: 0.43) // #5BC16E
    nonisolated static let deadline   = Color(red: 0.30, green: 0.65, blue: 1.0)  // #4DA6FF
    nonisolated static let recurrence = Color(red: 0.73, green: 0.55, blue: 1.0)  // #B98BFF
```

Leave `priorityLabel`, `recurrenceLabel`, and the size tokens (`cardRadius` etc.) unchanged.

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ThemeTests 2>&1 | tail -15
```
Expected: PASS (all `ThemeTests` green).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/Theme.swift WorkPanelTests/ThemeTests.swift
git commit -m "feat(theme): noir token 层 + 优先级/语义色调校"
```

---

## Task 2: Noir view modifiers + StatusDot

**Files:**
- Create: `WorkPanel/UI/NoirModifiers.swift`

- [ ] **Step 1: Create `WorkPanel/UI/NoirModifiers.swift`**

```swift
import SwiftUI

/// Warm Noir Utility 复用样式:卡片/列容器底、capsule badge、语义状态点。
/// 仅当某模式重复 ≥2 次才抽到此处,避免过度抽象(见 spec Approach A)。

extension View {
    /// 行/卡片底:surfaceSubtle 填充 + strokeStrong 细描边。
    func noirCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.strokeStrong, lineWidth: 0.7)
                )
        )
    }

    /// 列/象限容器底:安静 surface 填充 + stroke 细描边。
    func noirColumn() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 0.6)
                )
        )
    }

    /// 元数据 capsule:10 bold rounded,tint 前景 + 低透明 tint 底。用于 Text / Label。
    func noirBadge(_ tint: Color) -> some View {
        font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule(style: .continuous))
    }
}

/// 语义状态点;glow 仅给需要强调的状态(如 high 优先级)。
struct StatusDot: View {
    let color: Color
    var glow: Bool = false
    var size: CGFloat = Theme.priorityDotSize

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: glow ? color.opacity(0.5) : .clear, radius: glow ? 4 : 0)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project WorkPanel.xcodeproj -scheme WorkPanel -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WorkPanel/UI/NoirModifiers.swift
git commit -m "feat(ui): noirCard/noirColumn/noirBadge/StatusDot 复用样式"
```

---

## Task 3: TaskCardView noir restyle

**Files:**
- Modify: `WorkPanel/UI/TaskCardView.swift`

- [ ] **Step 1: Replace the `body` of `TaskCardView`**

Replace the whole `var body` with:

```swift
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.borderless)

            StatusDot(color: Theme.priority(task.priority),
                      glow: task.priority == .high)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: Theme.titleFontSize))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let d = task.deadline {
                        Text(d.formatted(date: .omitted, time: .shortened))
                            .noirBadge(d < .now ? Theme.priority(.high) : Theme.deadline)
                    }
                    if let rule = task.recurrence {
                        Label(Theme.recurrenceLabel(rule), systemImage: "repeat")
                            .labelStyle(.titleAndIcon)
                            .noirBadge(Theme.recurrence)
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text("#\(tag)").noirBadge(Theme.tag)
                    }
                }
            }

            Spacer(minLength: 0)
            trailing()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noirCard()
    }
```

(Removes the old `Circle().fill(Theme.priority(...))` dot, the per-element `.foregroundStyle(Theme...)` meta text, and the `controlBackgroundColor` background.)

- [ ] **Step 2: Build to verify**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Visual check**

Launch the app (or SwiftUI preview if present): a task card shows a dark `surfaceSubtle` row with hairline border, a small priority dot (red glows for high, amber for medium, faint gray for low), white title, and capsule badges for deadline/recurrence/tags. Overdue deadline badge is red.

- [ ] **Step 4: Commit**

```bash
git add WorkPanel/UI/TaskCardView.swift
git commit -m "feat(ui): TaskCardView noir 卡片 + capsule badge"
```

---

## Task 4: BoardView shell + lens tab strip (dark-only)

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift`

- [ ] **Step 1: Replace the shell `body` background block**

In `var body`, replace the modifier chain after the `VStack { header; Divider(); content }`:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onAppear { store.seedDefaultColumnsIfNeeded(); try? context.save() }
        .onKeyPress(.escape) { onClose(); return .handled }
```

(Replaces `.background(.ultraThinMaterial)`; keeps `clipShape`; adds stroke overlay + forces dark. The floating panel window already casts its own shadow — do not add a SwiftUI drop shadow here.)

- [ ] **Step 2: Replace `Divider()` with a noir hairline**

Change the line `Divider()` inside the `VStack` to:

```swift
            Rectangle().fill(Theme.stroke).frame(height: 1)
```

- [ ] **Step 3: Replace the `header` and add the lens tab strip + icon mapping**

Replace the `private var header` computed property with:

```swift
    private var header: some View {
        HStack(spacing: 12) {
            Text("看板")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(tasks.filter { !$0.isCompleted }.count) 项")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Spacer()
            lensTabStrip
            Spacer()

            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.borderless)
            Text("esc 收起")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var lensTabStrip: some View {
        HStack(spacing: 4) {
            ForEach(BoardViewMode.allCases) { m in
                let selected = m.rawValue == modeRaw
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.06)) { modeRaw = m.rawValue }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon(for: m))
                        Text(m.label)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background {
                        if selected {
                            Capsule(style: .continuous).fill(Theme.surfaceEmphasis)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Theme.surfaceSubtle))
    }

    private func icon(for m: BoardViewMode) -> String {
        switch m {
        case .kanban:   "rectangle.split.3x1"
        case .matrix:   "square.grid.2x2"
        case .today:    "calendar"
        case .priority: "flag"
        }
    }
```

(Removes the segmented `Picker` and its `.pickerStyle/.labelsHidden/.fixedSize`.)

- [ ] **Step 4: Build to verify**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Visual check**

The board shell is a black rounded panel with a hairline border. Header: bold white `看板` + dim count on the left, a dark capsule lens strip (icon + label per lens, selected segment filled `surfaceEmphasis`) centered, dim gear + `esc 收起` on the right. Switching lenses animates the highlight with a spring; no layout jump.

- [ ] **Step 6: Commit**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat(ui): BoardView 黑色外壳 + 透镜 tab 条 + dark-only"
```

---

## Task 5: PriorityLensView noir columns

**Files:**
- Modify: `WorkPanel/UI/PriorityLensView.swift`

- [ ] **Step 1: Restyle the `column(_:)` header and container**

In `private func column(_ p: Priority)`, replace the header `HStack` and the trailing `.background(...)` modifier:

Header `HStack`:
```swift
            HStack(spacing: 6) {
                StatusDot(color: Theme.priority(p), glow: p == .high, size: 8)
                Text(Theme.priorityLabel(p))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(list.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
```

Container background — replace `.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))` with:
```swift
        .noirColumn()
```

- [ ] **Step 2: Build to verify**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Visual check**

The 高/中/低 columns sit on quiet dark `surface` panels with hairline borders; each header shows a semantic dot, white bold label, dim count.

- [ ] **Step 4: Commit**

```bash
git add WorkPanel/UI/PriorityLensView.swift
git commit -m "feat(ui): PriorityLensView noir 列"
```

---

## Task 6: KanbanLensView noir columns + archive + buttons

**Files:**
- Modify: `WorkPanel/UI/KanbanLensView.swift`

- [ ] **Step 1: Restyle `columnView(_:)` header, add-task button, container**

In `columnView`, update the header `HStack`:
```swift
            HStack {
                Text(column.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .openTaskEditor,
                                                    object: TaskEditorView.Mode.create(columnID: column.id))
                } label: { Image(systemName: "plus").foregroundStyle(Theme.textTertiary) }
                .buttonStyle(.borderless)
                .frame(width: 22)
                Menu {
                    Button("重命名") { renameText = column.name; renaming = column }
                    Button("删除", role: .destructive) { store.delete(column); try? context.save() }
                        .disabled(columns.count <= 1)
                } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.textTertiary) }
                .menuStyle(.borderlessButton).frame(width: 22)
            }
```

Update the inline `+ 添加任务` button label:
```swift
                        Text("+ 添加任务")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .contentShape(Rectangle())
```

Replace the `columnView` container `.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))` with `.noirColumn()`.

- [ ] **Step 2: Restyle `archiveColumnView`**

Header `HStack`:
```swift
            HStack {
                Text("归档")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(archivedTasks.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
```

Archived row — keep the green check (success semantic), use noir text + card:
```swift
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(task.title).strikethrough()
                                .foregroundStyle(Theme.textMuted).lineLimit(1)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .noirCard()
                        .draggable(task.id.uuidString)
```

Replace the `archiveColumnView` container background with `.noirColumn()`.

- [ ] **Step 3: Restyle `addColumnButton`**

```swift
    private var addColumnButton: some View {
        Button { addingColumn = true } label: {
            Image(systemName: "plus").font(.title3)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 44, height: 60)
        }
        .buttonStyle(.plain)
        .noirColumn()
        .frame(alignment: .top)
    }
```

- [ ] **Step 4: Build to verify**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Visual check**

Custom columns + archive + add-column button are quiet dark panels. Column headers are white bold with dim count; `plus`/`ellipsis` are dim; `+ 添加任务` is warm orange. Archived rows show a green check and muted strikethrough title on a noir card.

- [ ] **Step 6: Commit**

```bash
git add WorkPanel/UI/KanbanLensView.swift
git commit -m "feat(ui): KanbanLensView noir 列/归档/按钮"
```

---

## Task 7: MatrixLensView noir quadrants

**Files:**
- Modify: `WorkPanel/UI/MatrixLensView.swift`

- [ ] **Step 1: Restyle `quadrant(important:urgent:action:)`**

Replace the header `HStack`, the divider `Rectangle`, the empty label, and the container background:

Header `HStack`:
```swift
            HStack(spacing: 6) {
                StatusDot(color: color, size: 8)
                Text(title(important: important, urgent: urgent))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(action)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
```

Divider:
```swift
            Rectangle().fill(color.opacity(0.45)).frame(height: 1)
```

Empty label:
```swift
                        Text("空").font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
```

Container — replace `.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))` with `.noirColumn()`.

- [ ] **Step 2: Build to verify**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Visual check**

The 2×2 quadrants are noir panels; each keeps its semantic color on the dot, the bold title, and the thin divider (red / blue / amber / gray). Action labels and empty `空` are dim.

- [ ] **Step 4: Commit**

```bash
git add WorkPanel/UI/MatrixLensView.swift
git commit -m "feat(ui): MatrixLensView noir 象限"
```

---

## Task 8: TodayLensView + ScrollEdgeFade fade into shell black

**Files:**
- Modify: `WorkPanel/UI/ScrollEdgeFade.swift`
- Modify: `WorkPanel/UI/TodayLensView.swift`

- [ ] **Step 1: Add a fade-color param to `ScrollEdgeFade`**

In `WorkPanel/UI/ScrollEdgeFade.swift`, change the extension function and the modifier to take a fade color that defaults to the shell black, and use a solid fill instead of `.ultraThinMaterial`:

```swift
extension View {
    func scrollEdgeFade(height: CGFloat = 22, fade: Color = Theme.panelBottom) -> some View {
        modifier(ScrollEdgeFade(bandHeight: height, fade: fade))
    }
}

private struct ScrollEdgeFade: ViewModifier {
    let bandHeight: CGFloat
    let fade: Color
    @State private var moreAbove = false
    @State private var moreBelow = false
```

And in `band(top:)` replace `.fill(.ultraThinMaterial)` with `.fill(fade)`:

```swift
    private func band(top: Bool) -> some View {
        Rectangle()
            .fill(fade)
            .mask(LinearGradient(colors: [.black, .clear],
                                 startPoint: top ? .top : .bottom,
                                 endPoint: top ? .bottom : .top))
            .frame(height: bandHeight)
            .allowsHitTesting(false)
    }
```

(All existing `.scrollEdgeFade()` call sites keep working via the default; they now fade into `panelBottom`.)

- [ ] **Step 2: Restyle the Today empty state**

In `WorkPanel/UI/TodayLensView.swift`, replace the empty-state `Text` with an SF-Symbol + text VStack:

```swift
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Text("今日无到期任务")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    ForEach(items) { LensCard(task: $0) }
                }
```

- [ ] **Step 3: Build to verify**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Visual check**

Today lens: noir cards; scrolling shows the top/bottom fade dissolving into the black shell (not a frosted band). Empty state is a centered dim seal icon + `今日无到期任务` (no emoji).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/ScrollEdgeFade.swift WorkPanel/UI/TodayLensView.swift
git commit -m "feat(ui): Today noir 卡片/空态 + 滚动渐变淡入黑底"
```

---

## Task 9 (OPTIONAL): Drop-target highlight

> Decide at execution time whether to include. Skipping leaves drag/drop behavior unchanged. Only do this if a visible drop target is wanted.

**Files:**
- Modify: `WorkPanel/UI/DeferredDrop.swift`
- Modify: `WorkPanel/UI/PriorityLensView.swift` (Kanban columns can follow the same `isTargeted` pattern later if wanted; not covered here)

- [ ] **Step 1: Expose `isTargeted` from `deferredDrop`**

Replace the `deferredDrop` extension in `WorkPanel/UI/DeferredDrop.swift`:

```swift
extension View {
    func deferredDrop(isTargeted: Binding<Bool>? = nil,
                      perform: @escaping (String) -> Void) -> some View {
        dropDestination(for: String.self) { dropped, _ in
            guard let payload = dropped.first else { return false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.18)) { perform(payload) }
            }
            return true
        } isTargeted: { hovering in
            isTargeted?.wrappedValue = hovering
        }
    }
}
```

(Existing call sites omit `isTargeted:` and keep compiling via the default `nil`.)

- [ ] **Step 2: Highlight the Priority column while targeted**

In `PriorityLensView.column(_:)`, add `@State`-backed targeting. Add near the top of the struct:
```swift
    @State private var dropTarget: Priority?
```
Change the column-level `.deferredDrop { payload in ... }` to bind targeting and add an overlay. Replace the trailing modifiers on the column container:
```swift
        .noirColumn()
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.accentStroke, lineWidth: dropTarget == p ? 1 : 0)
        )
        .deferredDrop(isTargeted: Binding(
            get: { dropTarget == p },
            set: { dropTarget = $0 ? p : nil }
        )) { payload in
            guard let id = UUID(uuidString: payload),
                  let task = tasks.first(where: { $0.id == id }) else { return }
            store.setPriority(task, to: p)
            try? context.save()
        }
```

- [ ] **Step 3: Build to verify**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Visual check**

Dragging a card over a priority column shows an orange `accentStroke` border on the hovered column; it clears on drop/exit. No residual cursor artifact (deferred drop still applies).

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/DeferredDrop.swift WorkPanel/UI/PriorityLensView.swift
git commit -m "feat(ui): 拖拽落点橙色高亮(可选)"
```

---

## Task 10: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Confirm no leftover light-mode surfaces**

Run:
```bash
grep -rn "ultraThinMaterial\|controlBackgroundColor\|Color.primary.opacity" WorkPanel/UI
```
Expected: no matches in the in-scope files (Theme/NoirModifiers/BoardView/TaskCardView/the four lenses/ScrollEdgeFade). `MarkdownPreview`, `TaskEditorView`, `SettingsView` are out of scope and may still match — that's expected.

- [ ] **Step 2: Full build**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run unit suites per-`-only-testing` (never the full bundle)**

Run each (UI-irrelevant suites confirm no logic regression):
```bash
for s in ThemeTests BoardStoreTests TodoStoreTests TodoTaskTests InputParserTests CaptureDraftTests AppSettingsTests; do
  xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/$s 2>&1 | tail -3
done
```
Expected: each prints `** TEST SUCCEEDED **`. (Per project memory: do NOT run the whole bundle — it can wedge `testmanagerd`.)

- [ ] **Step 4: Visual review against the checklist**

Open the app, cycle all four lenses, and confirm against `docs/design/ui-review-checklist.md`:
- Black shell dominant; orange only on interactive state (selected lens, hover, `+ 添加任务`, optional drop highlight).
- Semantic colors confined to dots / titles / thin dividers / badges; medium reads amber, not orange.
- Badges are capsules; overdue deadline badge is red.
- No layout jump on lens switch / hover; long titles/tags truncate.
- Anti-Slop Gate: no glass cards, no purple/blue gradient theme, no emoji as core control.

- [ ] **Step 5: Final commit (if any visual fixes were made)**

```bash
git add -A
git commit -m "fix(ui): Warm Noir review checklist 收尾"
```
(Skip if Step 4 required no changes.)
