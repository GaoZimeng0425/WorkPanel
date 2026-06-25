# Board Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared, non-persisted filter bar to the Board that filters tasks by tag, priority, urgency, and keyword across all lenses except Review.

**Architecture:** A single `@Observable BoardFilter` is held as `@State` in `BoardView` and injected via `.environment`. A funnel button in the header toggles a `BoardFilterBar` row. Each of the five filtered lenses reads the filter from the environment and routes its `@Query` task list through `filter.apply(...)` before rendering. `ReviewLensView` is untouched.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`@Test`). Default actor isolation is MainActor (project sets `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`), so pure value-logic members need no extra annotation unless used off-main.

Reference spec: `docs/superpowers/specs/2026-06-15-board-filter-design.md`

---

## File Structure

- **Create** `WorkPanel/Store/BoardFilter.swift` — the `@Observable BoardFilter` class: state + `apply` + `isActive` + `clear`.
- **Create** `WorkPanel/UI/Board/BoardFilterBar.swift` — the filter bar SwiftUI view (search field, priority pills, urgent pill, tag popover, clear button).
- **Create** `WorkPanelTests/BoardFilterTests.swift` — unit tests for `BoardFilter.apply`.
- **Modify** `WorkPanel/UI/Board/BoardView.swift` — hold filter state, inject environment, add funnel button + conditional bar slot, hide on Review.
- **Modify** `WorkPanel/UI/Board/KanbanLensView.swift` — route active + archived task sources through filter.
- **Modify** `WorkPanel/UI/Board/MatrixLensView.swift` — route `active` through filter.
- **Modify** `WorkPanel/UI/Board/PriorityLensView.swift` — route `items(_:)` through filter.
- **Modify** `WorkPanel/UI/Board/TodayLensView.swift` — filter the displayed committed list.
- **Modify** `WorkPanel/UI/Board/GanttLensView.swift` — route `rows` through filter.

New files under `WorkPanel/` and `WorkPanelTests/` are auto-included by Xcode's filesystem-synced groups — do NOT edit `project.pbxproj`.

---

## Task 1: `BoardFilter` model + tests

**Files:**
- Create: `WorkPanel/Store/BoardFilter.swift`
- Test: `WorkPanelTests/BoardFilterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `WorkPanelTests/BoardFilterTests.swift`:

```swift
import Foundation
import Testing
@testable import WorkPanel

@MainActor
struct BoardFilterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample() -> [TodoTask] {
        [
            TodoTask(title: "写周报", notes: "本周总结", deadline: now.addingTimeInterval(3600),
                     priority: .high, tags: ["工作"]),
            TodoTask(title: "买菜", notes: "西红柿鸡蛋", priority: .low, tags: ["生活"]),
            TodoTask(title: "读论文", notes: "", priority: .medium, tags: ["工作", "学习"]),
        ]
    }

    @Test func emptyFilterReturnsAllAndIsInactive() {
        let f = BoardFilter()
        #expect(f.isActive == false)
        #expect(f.apply(sample(), asOf: now).count == 3)
    }

    @Test func searchMatchesTitleOrNotesCaseInsensitively() {
        let f = BoardFilter()
        f.searchText = "周报"
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报"])
        f.searchText = "西红柿"          // notes hit
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["买菜"])
        f.searchText = "  "             // whitespace-only → inactive
        #expect(f.isActive == false)
        #expect(f.apply(sample(), asOf: now).count == 3)
    }

    @Test func tagsMatchAnySelected() {
        let f = BoardFilter()
        f.tags = ["工作"]
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报", "读论文"])
        f.tags = ["生活", "学习"]        // OR across selected tags
        #expect(Set(f.apply(sample(), asOf: now).map(\.title)) == ["买菜", "读论文"])
    }

    @Test func prioritiesMatchSelectedSet() {
        let f = BoardFilter()
        f.priorities = [.high, .low]
        #expect(Set(f.apply(sample(), asOf: now).map(\.title)) == ["写周报", "买菜"])
    }

    @Test func urgentOnlyKeepsUrgent() {
        let f = BoardFilter()
        f.urgentOnly = true
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报"])
    }

    @Test func dimensionsCombineWithAnd() {
        let f = BoardFilter()
        f.tags = ["工作"]
        f.priorities = [.high]
        #expect(f.apply(sample(), asOf: now).map(\.title) == ["写周报"])
    }

    @Test func clearResetsEverything() {
        let f = BoardFilter()
        f.searchText = "x"; f.tags = ["工作"]; f.priorities = [.high]; f.urgentOnly = true
        f.clear()
        #expect(f.isActive == false)
        #expect(f.searchText.isEmpty)
        #expect(f.tags.isEmpty)
        #expect(f.priorities.isEmpty)
        #expect(f.urgentOnly == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme WorkPanel -only-testing:WorkPanelTests/BoardFilterTests 2>&1 | tail -20`
Expected: FAIL — compile error, `BoardFilter` is not defined.

- [ ] **Step 3: Write minimal implementation**

Create `WorkPanel/Store/BoardFilter.swift`:

```swift
import Foundation
import Observation

/// 看板共享过滤器:跨透镜筛选任务。条件不持久化(随 BoardView 重建清空)。
/// 维度之间是 AND;同一维度内是 OR。Review 透镜不消费本对象。
@Observable
final class BoardFilter {
    var searchText: String = ""
    var tags: Set<String> = []
    var priorities: Set<Priority> = []
    var urgentOnly: Bool = false

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    var isActive: Bool {
        !trimmedSearch.isEmpty || !tags.isEmpty || !priorities.isEmpty || urgentOnly
    }

    /// 只过滤,不排序、不剔除已完成——是否排除 completed 由各透镜自行决定。
    func apply(_ tasks: [TodoTask], asOf now: Date = .now) -> [TodoTask] {
        guard isActive else { return tasks }
        let q = trimmedSearch
        return tasks.filter { t in
            if !q.isEmpty,
               !t.title.localizedCaseInsensitiveContains(q),
               !t.notes.localizedCaseInsensitiveContains(q) { return false }
            if !tags.isEmpty, tags.isDisjoint(with: Set(t.tags)) { return false }
            if !priorities.isEmpty, !priorities.contains(t.priority) { return false }
            if urgentOnly, !t.isUrgent(asOf: now) { return false }
            return true
        }
    }

    func clear() {
        searchText = ""
        tags = []
        priorities = []
        urgentOnly = false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WorkPanel -only-testing:WorkPanelTests/BoardFilterTests 2>&1 | tail -20`
Expected: PASS — 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/Store/BoardFilter.swift WorkPanelTests/BoardFilterTests.swift
git commit -m "feat(board): add BoardFilter model with apply/clear logic"
```

---

## Task 2: `BoardFilterBar` view

**Files:**
- Create: `WorkPanel/UI/Board/BoardFilterBar.swift`

No unit test — UI component (project convention: SwiftUI interaction not XCUITested; logic lives in `BoardFilter`, already covered). Verification is a successful build in Task 5.

- [ ] **Step 1: Create the view**

Create `WorkPanel/UI/Board/BoardFilterBar.swift`:

```swift
import SwiftUI
import SwiftData

/// 看板过滤栏:搜索 + 优先级药丸 + 紧急药丸 + 标签多选 + 清除。
/// 写入注入环境的 BoardFilter;各透镜读取并应用。
struct BoardFilterBar: View {
    @Bindable var filter: BoardFilter
    @Query(sort: \Tag.order) private var allTags: [Tag]

    @State private var showTags = false

    var body: some View {
        HStack(spacing: 10) {
            searchField
            priorityPills
            urgentPill
            tagButton
            Spacer(minLength: 0)
            if filter.isActive {
                Button("清除") { filter.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            TextField("搜索标题/备注", text: $filter.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 140)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.surfaceSubtle, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Theme.stroke, lineWidth: 0.6))
    }

    private var priorityPills: some View {
        HStack(spacing: 4) {
            ForEach([Priority.high, .medium, .low], id: \.self) { p in
                togglePill(label: Theme.priorityLabel(p),
                           tint: Theme.priority(p),
                           on: filter.priorities.contains(p)) {
                    if filter.priorities.contains(p) { filter.priorities.remove(p) }
                    else { filter.priorities.insert(p) }
                }
            }
        }
    }

    private var urgentPill: some View {
        togglePill(label: "⚡ 紧急", tint: Theme.accent, on: filter.urgentOnly) {
            filter.urgentOnly.toggle()
        }
    }

    private var tagButton: some View {
        Button { showTags = true } label: {
            HStack(spacing: 4) {
                Text(filter.tags.isEmpty ? "标签" : "标签 \(filter.tags.count)")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(filter.tags.isEmpty ? Theme.textSecondary : Theme.accentText)
            .noirPickerPill()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTags, arrowEdge: .bottom) { tagPopover }
    }

    private var tagPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if allTags.isEmpty {
                    Text("还没有标签")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                }
                ForEach(allTags) { tag in
                    Button {
                        if filter.tags.contains(tag.name) { filter.tags.remove(tag.name) }
                        else { filter.tags.insert(tag.name) }
                    } label: {
                        HStack {
                            Text("#\(tag.name)").foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if filter.tags.contains(tag.name) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .font(.system(size: 12))
                        .contentShape(Rectangle())
                        .padding(.horizontal, 9).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 200, height: min(260, CGFloat(max(allTags.count, 1)) * 34 + 16))
        .background(Theme.panelBottom)
        .preferredColorScheme(.dark)
    }

    private func togglePill(label: String, tint: Color, on: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.black : tint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(on ? tint : Color.clear))
                .overlay(Capsule(style: .continuous).stroke(tint.opacity(0.7), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add WorkPanel/UI/Board/BoardFilterBar.swift
git commit -m "feat(board): add BoardFilterBar view"
```

---

## Task 3: Wire filter into `BoardView`

**Files:**
- Modify: `WorkPanel/UI/Board/BoardView.swift`

- [ ] **Step 1: Add filter state and showFilter flag**

In `BoardView`, add these properties alongside the existing `@State private var showPlanning = false` (after line 12):

```swift
    @State private var showPlanning = false
    @State private var filter = BoardFilter()
    @State private var showFilter = false
```

- [ ] **Step 2: Inject the filter into the environment and add the bar slot**

Replace the body's top `VStack` (lines 18-23) so the bar appears between the header and the divider, and the whole tree gets the environment object. Change:

```swift
        VStack(spacing: 0) {
            resizeHandle
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)
            content
        }
```

to:

```swift
        VStack(spacing: 0) {
            resizeHandle
            header
            if showFilter && mode != .review {
                BoardFilterBar(filter: filter)
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
            content
        }
        .environment(filter)
```

(The `.environment(filter)` chains onto the `VStack`, before the existing `.frame(...)` modifier on line 24.)

- [ ] **Step 3: Add the funnel button to the header**

In `header` (the `HStack`), insert the funnel button immediately before the existing gear button (before the `Button { NotificationCenter.default.post(name: .openSettings ...` block at line 90). Add:

```swift
            if mode != .review {
                Button { showFilter.toggle() } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(filter.isActive ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(NoirIconButtonStyle())
                .help("过滤")
                .accessibilityLabel("过滤")
            }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -scheme WorkPanel 2>&1 | tail -15`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add WorkPanel/UI/Board/BoardView.swift
git commit -m "feat(board): wire BoardFilter into BoardView header and bar"
```

---

## Task 4: Apply the filter in the five lenses

**Files:**
- Modify: `WorkPanel/UI/Board/KanbanLensView.swift`
- Modify: `WorkPanel/UI/Board/MatrixLensView.swift`
- Modify: `WorkPanel/UI/Board/PriorityLensView.swift`
- Modify: `WorkPanel/UI/Board/TodayLensView.swift`
- Modify: `WorkPanel/UI/Board/GanttLensView.swift`

Each lens reads the shared filter from the environment and routes its task source through `filter.apply(...)`. `ReviewLensView` is intentionally not modified.

- [ ] **Step 1: KanbanLensView — add environment + filter active and archived sources**

Add the environment property after the existing `@Query private var columns` (line 9):

```swift
    @Environment(BoardFilter.self) private var filter
```

In `activeTasks(in:)` (lines 30-33), wrap the source:

```swift
    private func activeTasks(in column: BoardColumn) -> [TodoTask] {
        filter.apply(tasks).filter { !$0.isCompleted && columnID(for: $0) == column.id }
             .sorted { $0.boardOrder < $1.boardOrder }
    }
```

In `archivedTasks` (lines 35-38), wrap the source:

```swift
    private var archivedTasks: [TodoTask] {
        filter.apply(tasks).filter { $0.isCompleted }
             .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
```

- [ ] **Step 2: MatrixLensView — add environment + filter `active`**

Add after `@Query private var tasks` (line 7):

```swift
    @Environment(BoardFilter.self) private var filter
```

Change `active` (line 9):

```swift
    private var active: [TodoTask] { filter.apply(tasks).filter { !$0.isCompleted } }
```

- [ ] **Step 3: PriorityLensView — add environment + filter `items`**

Add after `@Query private var tasks` (line 7):

```swift
    @Environment(BoardFilter.self) private var filter
```

Change `items(_:)` (lines 11-14):

```swift
    private func items(_ p: Priority) -> [TodoTask] {
        filter.apply(tasks).filter { !$0.isCompleted && $0.priority == p }
             .sorted { $0.boardOrder < $1.boardOrder }
    }
```

- [ ] **Step 4: TodayLensView — add environment + filter the displayed committed list**

Add after `@Query private var tasks` (line 10):

```swift
    @Environment(BoardFilter.self) private var filter
```

Change `committed` (line 15) so display, count, and reorder all use the filtered list consistently. When the filter is inactive, `apply` returns the list unchanged, so behavior is identical to today:

```swift
    private var committed: [TodoTask] { filter.apply(store.committedTasks(on: now)) }
```

Note: `dueNotCommittedCount` already derives from the raw `tasks` query and the `committed` id set; leave it unchanged. When a filter is active it counts due-but-not-committed tasks against the filtered committed set, which is acceptable for a temporary filter.

- [ ] **Step 5: GanttLensView — add environment + filter `rows`**

Add after `@Query(sort: \BoardColumn.order) private var columns` (line 9):

```swift
    @Environment(BoardFilter.self) private var filter
```

Change the `rows` source (line 23) from:

```swift
        let rows = tasks.filter { !$0.isCompleted }
```

to:

```swift
        let rows = filter.apply(tasks).filter { !$0.isCompleted }
```

- [ ] **Step 6: Build to verify all lenses compile**

Run: `xcodebuild build -scheme WorkPanel 2>&1 | tail -15`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WorkPanel/UI/Board/KanbanLensView.swift WorkPanel/UI/Board/MatrixLensView.swift WorkPanel/UI/Board/PriorityLensView.swift WorkPanel/UI/Board/TodayLensView.swift WorkPanel/UI/Board/GanttLensView.swift
git commit -m "feat(board): apply shared filter across all lenses except Review"
```

---

## Task 5: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the BoardFilter test suite**

Run: `xcodebuild test -scheme WorkPanel -only-testing:WorkPanelTests/BoardFilterTests 2>&1 | tail -20`
Expected: PASS — all 7 tests.

- [ ] **Step 2: Run the existing board-related suites to confirm no regression**

Run per-suite (full-bundle `xcodebuild test` can wedge testmanagerd — use `-only-testing`):

```bash
xcodebuild test -scheme WorkPanel \
  -only-testing:WorkPanelTests/BoardStoreTests \
  -only-testing:WorkPanelTests/ReorderTests \
  -only-testing:WorkPanelTests/BoardViewModeReviewTests 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 3: Build the app**

Run: `xcodebuild build -scheme WorkPanel 2>&1 | tail -15`
Expected: `** BUILD SUCCEEDED **`

---

## Self-Review Notes

- **Spec coverage:** tags/priority/urgency/keyword (Task 1 `apply`); shared across lenses via environment (Tasks 3-4); Review excluded (funnel hidden + bar suppressed in Task 3, lens unmodified in Task 4); non-persisted (`@State` in BoardView, no AppStorage); funnel highlights when `isActive`; tag popover from `Tag` registry; priority pills via `Theme.priority`/`priorityLabel`; clear button; no special empty state (relies on each lens's existing empty text).
- **Type consistency:** `BoardFilter` properties (`searchText`, `tags: Set<String>`, `priorities: Set<Priority>`, `urgentOnly`) and methods (`apply(_:asOf:)`, `isActive`, `clear`) are referenced identically in tests, the bar, BoardView, and all lenses.
- **Known tradeoff (Today lens):** drag-reorder operates on the filtered visible list when a filter is active; reordering relative to hidden items is imprecise. Accepted as an edge case for a temporary filter; unfiltered behavior is unchanged because `apply` is a no-op when inactive.
