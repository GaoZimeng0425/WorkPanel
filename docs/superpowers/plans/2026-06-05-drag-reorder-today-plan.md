# 今日规划 拖动排序 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让「今日承诺 (TodayLensView)」与「开工规划 (PlanningView)」两个界面都支持拖动排序,且顺序持久化。

**Architecture:** 复用项目已有的拖拽落点模式(`LensCard(draggable:)` 发出 `task.id.uuidString` + `.deferredDrop` 落点 + insert-before 索引语义)。两处共用一个纯函数 `reorderInsertingBefore` 做数组重排。TodayLensView 持久化到 `DayPlan.committedTaskIDs`;PlanningView 持久化到新增的 `TodoTask.planOrder`(仅在规划页候选排序中消费,不影响其他列表)。

**Tech Stack:** SwiftUI + SwiftData,Swift Testing 框架(`import Testing`),内存 `ModelContext`。测试用 `xcodebuild test`,**按 suite 单独 `-only-testing`**(全 bundle 跑会 wedge testmanagerd)。

---

## File Structure

- Create: `WorkPanel/Store/Reorder.swift` — 纯函数 `reorderInsertingBefore`。
- Create: `WorkPanelTests/ReorderTests.swift` — 纯函数测试。
- Modify: `WorkPanel/Store/PlanStore.swift` — 新增 `reorder(_:to:on:)` 与 `reorderPlan(_:move:before:)`。
- Modify: `WorkPanelTests/PlanStoreTests.swift` — 新增两个 store 方法的测试。
- Modify: `WorkPanel/Models/TodoTask.swift` — 新增 `planOrder: Int = 0`。
- Modify: `WorkPanel/UI/TodayLensView.swift` — 卡片可拖 + 落点。
- Modify: `WorkPanel/UI/PlanningView.swift` — 候选排序加 planOrder 主键 + 行可拖 + 落点。

`reorderInsertingBefore` 语义(与 `BoardStore.move` 的数组部分一致):移除 `id`;若原索引 `< targetIndex` 则目标索引 `-1`;clamp 到 `[0, count-after-removal]`;插回。容器追加传 `targetIndex == count`。

---

## Task 1: 共享纯函数 reorderInsertingBefore

**Files:**
- Create: `WorkPanel/Store/Reorder.swift`
- Test: `WorkPanelTests/ReorderTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `WorkPanelTests/ReorderTests.swift`:

```swift
import Testing
import Foundation
@testable import WorkPanel

struct ReorderTests {
    @Test func moveForwardInsertsBeforeTarget() {
        let a = UUID(), b = UUID(), c = UUID()
        // a 原索引 0 < 目标 2 → 移除后落到 index 1
        #expect(reorderInsertingBefore([a, b, c], move: a, before: 2) == [b, a, c])
    }

    @Test func moveBackwardInsertsBeforeTarget() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(reorderInsertingBefore([a, b, c], move: c, before: 0) == [c, a, b])
    }

    @Test func moveToContainerAppends() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(reorderInsertingBefore([a, b, c], move: a, before: 3) == [b, c, a])
    }

    @Test func unknownIDNoOp() {
        let a = UUID(), b = UUID()
        #expect(reorderInsertingBefore([a, b], move: UUID(), before: 0) == [a, b])
    }

    @Test func singleElementStable() {
        let a = UUID()
        #expect(reorderInsertingBefore([a], move: a, before: 0) == [a])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ReorderTests`
Expected: 编译失败,`cannot find 'reorderInsertingBefore' in scope`。

- [ ] **Step 3: 写实现**

创建 `WorkPanel/Store/Reorder.swift`:

```swift
import Foundation

/// 把 `id` 在 `ids` 中移动到「第 targetIndex 个元素之前」(insert-before),返回新数组。
/// 与 BoardStore.move 的数组语义一致:同列表向下移动时目标索引前移一位;越界 clamp;
/// id 不存在则原样返回。容器追加场景传 targetIndex == ids.count。
/// nonisolated:项目默认 MainActor 隔离,纯函数显式 opt-out 以便测试在非隔离上下文调用。
nonisolated func reorderInsertingBefore(_ ids: [UUID], move id: UUID, before targetIndex: Int) -> [UUID] {
    guard let old = ids.firstIndex(of: id) else { return ids }
    var rest = ids
    rest.remove(at: old)
    var t = targetIndex
    if old < targetIndex { t -= 1 }
    t = max(0, min(t, rest.count))
    rest.insert(id, at: t)
    return rest
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ReorderTests`
Expected: PASS(5 个测试全过)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/Reorder.swift WorkPanelTests/ReorderTests.swift
git commit -m "feat(reorder): pure reorderInsertingBefore helper + tests"
```

---

## Task 2: TodoTask.planOrder 字段

**Files:**
- Modify: `WorkPanel/Models/TodoTask.swift:18`

- [ ] **Step 1: 加字段**

在 `WorkPanel/Models/TodoTask.swift` 的 `var boardOrder: Int` 一行之后插入新的存储属性(带声明级默认值 → SwiftData 轻量迁移自动处理,旧数据为 0,无需改 init):

```swift
    var boardOrder: Int
    var planOrder: Int = 0           // 开工规划页手动排序;仅 PlanningView 候选排序消费
    var urgencyOverride: Bool?
```

(`boardOrder` 与 `urgencyOverride` 行已存在,只新增中间一行 `planOrder`。)

- [ ] **Step 2: 编译确认不破坏现有测试**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: PASS(现有测试不受影响,planOrder 有默认值不需改任何 init 调用点)。

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/Models/TodoTask.swift
git commit -m "feat(model): add TodoTask.planOrder for planning-page manual order"
```

---

## Task 3: PlanStore.reorder(承诺顺序)

**Files:**
- Modify: `WorkPanel/Store/PlanStore.swift`(在 `toggle` 方法之后)
- Test: `WorkPanelTests/PlanStoreTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WorkPanelTests/PlanStoreTests.swift` 的最后一个 `}`(struct 结束)之前加入:

```swift
    @Test func reorderMovesCommittedTask() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let t1 = TodoTask(title: "一"), t2 = TodoTask(title: "二"), t3 = TodoTask(title: "三")
        [t1, t2, t3].forEach { context.insert($0); store.toggle($0, on: day) }
        // 初始承诺顺序 [t1, t2, t3];把 t3 移到最前(index 0)
        store.reorder(t3.id, to: 0, on: day)
        #expect(store.committedTasks(on: day).map(\.id) == [t3.id, t1.id, t2.id])
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests/reorderMovesCommittedTask`
Expected: 编译失败,`value of type 'PlanStore' has no member 'reorder'`。

- [ ] **Step 3: 写实现**

在 `WorkPanel/Store/PlanStore.swift` 的 `toggle(_:on:)` 方法(以 `}` 结束那段)之后插入:

```swift
    /// 重排 day 当天承诺任务的顺序:把 id 移到「第 index 个之前」(容器追加传 index == 数量)。
    func reorder(_ id: UUID, to index: Int, on day: Date) {
        let p = ensurePlan(on: day)
        p.committedTaskIDs = reorderInsertingBefore(p.committedTaskIDs, move: id, before: index)
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: PASS(含原有测试 + 新增 `reorderMovesCommittedTask`)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/PlanStore.swift WorkPanelTests/PlanStoreTests.swift
git commit -m "feat(plan): PlanStore.reorder for committed-task order"
```

---

## Task 4: PlanStore.reorderPlan(候选 planOrder 重排)

**Files:**
- Modify: `WorkPanel/Store/PlanStore.swift`(在 Task 3 新增的 `reorder` 之后)
- Test: `WorkPanelTests/PlanStoreTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WorkPanelTests/PlanStoreTests.swift` 的 struct 结束 `}` 之前加入:

```swift
    @Test func reorderPlanRenumbersPlanOrder() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let t1 = TodoTask(title: "一"), t2 = TodoTask(title: "二"), t3 = TodoTask(title: "三")
        [t1, t2, t3].forEach { context.insert($0) }
        // 当前候选顺序 [t1, t2, t3];把 t3 拖到最前
        store.reorderPlan([t1.id, t2.id, t3.id], move: t3.id, before: 0)
        #expect(t3.planOrder == 0)
        #expect(t1.planOrder == 1)
        #expect(t2.planOrder == 2)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests/reorderPlanRenumbersPlanOrder`
Expected: 编译失败,`value of type 'PlanStore' has no member 'reorderPlan'`。

- [ ] **Step 3: 写实现**

在 `WorkPanel/Store/PlanStore.swift` 的 `reorder(_:to:on:)` 之后插入:

```swift
    /// 候选拖动重排(仅作用于规划页):按 insert-before 算出新顺序后,
    /// 把这些任务的 planOrder 重写为 0,1,2,…。
    func reorderPlan(_ currentOrder: [UUID], move id: UUID, before index: Int) {
        let newOrder = reorderInsertingBefore(currentOrder, move: id, before: index)
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        for (i, tid) in newOrder.enumerated() { byID[tid]?.planOrder = i }
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: PASS(含新增 `reorderPlanRenumbersPlanOrder`)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/PlanStore.swift WorkPanelTests/PlanStoreTests.swift
git commit -m "feat(plan): PlanStore.reorderPlan renumbers candidate planOrder"
```

---

## Task 5: TodayLensView 拖动落点(UI)

**Files:**
- Modify: `WorkPanel/UI/TodayLensView.swift`

(UI 改动,无单元测试 —— 合成拖拽无法在 XCUITest 触发 `.draggable`/`.dropDestination`;落点逻辑已在 Task 3 的 store 测试覆盖。本任务用编译 + 手动验证。)

- [ ] **Step 1: 卡片可拖 + 每张卡片落点**

在 `WorkPanel/UI/TodayLensView.swift` 中,把渲染承诺卡片的这一行:

```swift
                    ForEach(committed) { LensCard(task: $0) }
```

替换为:

```swift
                    ForEach(Array(committed.enumerated()), id: \.element.id) { index, task in
                        LensCard(task: task, draggable: true)
                            .deferredDrop { dropReorder($0, before: index) }
                    }
```

- [ ] **Step 2: 容器追加落点**

在同一个 `VStack(spacing: 8) { ... }`(包住 emptyState / 卡片列表的那个)的右括号之后、`.frame(maxWidth: 560)` 之前,加一行容器级落点(拖到空白处 = 追加到末尾):

```swift
            }
            .deferredDrop { dropReorder($0, before: committed.count) }
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .padding(12)
```

(原本是 `}` 紧跟 `.frame(maxWidth: 560)...`;只在两者之间插入 `.deferredDrop { ... }` 一行。)

- [ ] **Step 3: 加落点回调方法**

在 `TodayLensView` 内、`body` 之后(`emptyState` 之前或之后均可)加入私有方法:

```swift
    private func dropReorder(_ payload: String, before index: Int) {
        guard let id = UUID(uuidString: payload) else { return }
        store.reorder(id, to: index, on: now)
        try? context.save()
    }
```

- [ ] **Step 4: 编译验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。

手动验证(可选,启动 app):看板切到「今日」透镜,拖动承诺卡片重排,松手后顺序改变;收起再展开看板,顺序保留(已写入 `committedTaskIDs`)。

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/UI/TodayLensView.swift
git commit -m "feat(today): drag-to-reorder committed tasks"
```

---

## Task 6: PlanningView 拖动落点 + planOrder 排序(UI)

**Files:**
- Modify: `WorkPanel/UI/PlanningView.swift`

(UI 改动,落点逻辑已在 Task 4 的 store 测试覆盖。编译 + 手动验证。)

- [ ] **Step 1: 候选排序加 planOrder 主键**

在 `WorkPanel/UI/PlanningView.swift` 的 `candidates` 计算属性里,把 `.sorted { lhs, rhs in` 闭包的**第一行**(当前是 `let lc = carriedIDs.contains(lhs.id), rc = carriedIDs.contains(rhs.id)`)之前插入 planOrder 比较,使其成为主排序键:

```swift
            .sorted { lhs, rhs in
                if lhs.planOrder != rhs.planOrder { return lhs.planOrder < rhs.planOrder }
                let lc = carriedIDs.contains(lhs.id), rc = carriedIDs.contains(rhs.id)
                if lc != rc { return lc }
                let ls = suggested(lhs, cal: cal), rs = suggested(rhs, cal: cal)
                if ls != rs { return ls }
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
```

(只新增 `if lhs.planOrder != rhs.planOrder { ... }` 一行;其余保持不变。首次拖动前所有 planOrder==0,排序逐字等同现状。)

- [ ] **Step 2: 候选行可拖 + 每行落点**

把 body 里的:

```swift
                    ForEach(candidates) { task in row(task) }
```

替换为:

```swift
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, task in
                        row(task)
                            .draggable(task.id.uuidString)
                            .deferredDrop { dropReorder($0, before: index) }
                    }
```

- [ ] **Step 3: 容器追加落点**

在包住该 `ForEach` 的 `VStack(spacing: 8) { ... }` 的右括号之后、`.frame(maxWidth: 560)` 之前插入容器级落点:

```swift
                }
                .deferredDrop { dropReorder($0, before: candidates.count) }
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .padding(12)
```

(原本 `}` 紧跟 `.frame(maxWidth: 560)...`;只在两者之间插入 `.deferredDrop { ... }` 一行。)

- [ ] **Step 4: 加落点回调方法**

在 `PlanningView` 内、`dismiss()` 方法之后加入私有方法:

```swift
    private func dropReorder(_ payload: String, before index: Int) {
        guard let id = UUID(uuidString: payload) else { return }
        store.reorderPlan(candidates.map(\.id), move: id, before: index)
        try? context.save()
    }
```

- [ ] **Step 5: 编译验证**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。

手动验证(可选):触发开工规划,拖动候选行重排,松手后顺序改变;关掉规划页再次触发,手动顺序保留(已写入 `planOrder`)。

- [ ] **Step 6: 提交**

```bash
git add WorkPanel/UI/PlanningView.swift
git commit -m "feat(planning): drag-to-reorder candidates, persisted via planOrder"
```

---

## Self-Review

**Spec coverage:**
- 共享纯函数 → Task 1 ✓
- TodayLensView 持久拖动(committedTaskIDs)→ Task 3(逻辑)+ Task 5(UI)✓
- PlanningView 持久拖动(planOrder,仅规划页)→ Task 2(字段)+ Task 4(逻辑)+ Task 6(排序+UI)✓
- 首次拖动前零行为变化 → Task 6 Step 1 注释 + planOrder 默认 0 ✓
- 不重构 BoardStore.move / 不动 TaskFilter.sortRule → 计划中未触碰 ✓
- 测试只覆盖逻辑不覆盖手势 → Task 1/3/4 单元测试,Task 5/6 编译+手动 ✓

**类型一致性:** `reorderInsertingBefore(_:move:before:)`、`PlanStore.reorder(_:to:on:)`、`PlanStore.reorderPlan(_:move:before:)`、`TodoTask.planOrder`、各 View 的 `dropReorder(_:before:)` 签名在定义与调用处一致 ✓

**Placeholder 扫描:** 无 TBD/TODO,每个代码步骤都有完整代码 ✓
