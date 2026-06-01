# 每日开工规划仪式（今日承诺 + 数据复盘）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 WorkPanel 加一个「每日开工规划」仪式——每天主动挑出「今日承诺」，静默记录承诺/完成/顺延，并在复盘透镜把数据反映回来；忠于「只记录、不干预」哲学。

**Architecture:** 只新增一个 SwiftData 模型 `DayPlan`（每日承诺快照），不动 `TodoTask`。规划读写与跨天触发判定放进新的 `@MainActor` `PlanStore`；复盘统计抽成纯函数 `PlanStats`（无副作用、不需容器，便于单测）。UI 层：新增 `PlanningView`（开工规划）、改造 `TodayLensView`（承诺驱动）、新增第 5 个透镜 `ReviewLensView`（复盘）。

**Tech Stack:** Swift 6（严格并发），SwiftUI + SwiftData，Swift Testing（`import Testing`），`@AppStorage`。

**测试约定（重要）:** 全量 `xcodebuild test` 会卡死 testmanagerd。每个测试步骤都用 per-suite `-only-testing` 跑：
`xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/<SuiteName>`

---

## 文件结构

| 文件 | 操作 | 职责 |
|---|---|---|
| `WorkPanel/Models/DayPlan.swift` | 新建 | `@Model DayPlan`：某日承诺的任务 ID 快照 |
| `WorkPanel/WorkPanelApp.swift` | 改 | schema 加入 `DayPlan.self` |
| `WorkPanel/Store/AppSettings.swift` | 改 | 新增 `Key.lastPlannedDay` |
| `WorkPanel/Store/PlanStore.swift` | 新建 | 读写今日 `DayPlan`、toggle 承诺、跨天触发判定 |
| `WorkPanel/Store/PlanStats.swift` | 新建 | 复盘统计纯函数（承诺/完成/顺延/超载） |
| `WorkPanel/UI/PlanningView.swift` | 新建 | 开工规划界面 |
| `WorkPanel/UI/TodayLensView.swift` | 改 | 由 deadline 驱动改为承诺驱动 |
| `WorkPanel/UI/ReviewLensView.swift` | 新建 | 复盘透镜视图 |
| `WorkPanel/Models/BoardViewMode.swift` | 改 | 新增 `case review` |
| `WorkPanel/UI/BoardView.swift` | 改 | 透镜分发加 review；onAppear 触发开工规划 |
| `WorkPanelTests/PlanStoreTests.swift` | 新建 | PlanStore 单测 |
| `WorkPanelTests/PlanStatsTests.swift` | 新建 | PlanStats 单测 |

---

## Task 1: DayPlan 模型 + 注册 schema

**Files:**
- Create: `WorkPanel/Models/DayPlan.swift`
- Modify: `WorkPanel/WorkPanelApp.swift:11`
- Test: `WorkPanelTests/PlanStoreTests.swift`（先建文件，仅放本任务的持久化冒烟测试）

- [ ] **Step 1: 写失败测试 — DayPlan 能在内存容器里持久化**

`WorkPanelTests/PlanStoreTests.swift`：

```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct PlanStoreTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    @Test func dayPlanPersists() throws {
        let context = try makeContext()
        let plan = DayPlan(day: Date(timeIntervalSinceReferenceDate: 0), committedTaskIDs: [UUID()])
        context.insert(plan)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<DayPlan>()).count == 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: 编译失败 / "cannot find 'DayPlan' in scope"

- [ ] **Step 3: 新建 DayPlan 模型**

`WorkPanel/Models/DayPlan.swift`：

```swift
import Foundation
import SwiftData

/// 某个自然日的「今日承诺」快照:那天主动挑出要推进的任务 ID。
/// 只存 ID,不建关系,删除任务时无级联;渲染时按 ID 取任务,取不到即跳过。
@Model
final class DayPlan {
    var day: Date                  // 归一化到当天 00:00(Calendar.startOfDay)
    var committedTaskIDs: [UUID]

    init(day: Date, committedTaskIDs: [UUID] = []) {
        self.day = day
        self.committedTaskIDs = committedTaskIDs
    }
}
```

- [ ] **Step 4: 把 DayPlan 加入 schema**

`WorkPanel/WorkPanelApp.swift:11`，把：

```swift
let schema = Schema([TodoTask.self, BoardColumn.self])
```

改为：

```swift
let schema = Schema([TodoTask.self, BoardColumn.self, DayPlan.self])
```

- [ ] **Step 5: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: PASS（1 test）

- [ ] **Step 6: 提交**

```bash
git add WorkPanel/Models/DayPlan.swift WorkPanel/WorkPanelApp.swift WorkPanelTests/PlanStoreTests.swift
git commit -m "feat(plan): DayPlan 模型 + 注册 schema"
```

---

## Task 2: PlanStore — 读写今日承诺 + toggle

**Files:**
- Create: `WorkPanel/Store/PlanStore.swift`
- Test: `WorkPanelTests/PlanStoreTests.swift`（追加）

- [ ] **Step 1: 写失败测试 — ensurePlan/toggle/committedTasks**

在 `PlanStoreTests` 里追加（保留 Task 1 的 `makeContext`）：

```swift
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
    }

    @Test func toggleAddsAndRemovesCommitment() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let task = TodoTask(title: "写周报")
        context.insert(task)

        store.toggle(task, on: day)
        #expect(store.isCommitted(task, on: day))
        store.toggle(task, on: day)
        #expect(!store.isCommitted(task, on: day))
    }

    @Test func ensurePlanReusesSameDayPlan() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 21))!
        _ = store.ensurePlan(on: morning)
        _ = store.ensurePlan(on: evening)
        #expect(try context.fetch(FetchDescriptor<DayPlan>()).count == 1)
    }

    @Test func committedTasksSkipsDeletedIDs() throws {
        let context = try makeContext()
        let store = PlanStore(context: context, calendar: calendar)
        let task = TodoTask(title: "活儿")
        context.insert(task)
        store.toggle(task, on: day)
        context.delete(task)
        #expect(store.committedTasks(on: day).isEmpty)   // ID 取不到 → 跳过,不崩
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: 编译失败 / "cannot find 'PlanStore' in scope"

- [ ] **Step 3: 新建 PlanStore**

`WorkPanel/Store/PlanStore.swift`：

```swift
import Foundation
import SwiftData

@MainActor
final class PlanStore {
    let context: ModelContext
    let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// 返回 day 所在自然日的 DayPlan(若有)。谓词无法表达 calendar 比较,内存过滤(N 小)。
    func plan(on day: Date) -> DayPlan? {
        let all = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        return all.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// 取或建 day 当天的 DayPlan,day 归一化到 00:00。
    @discardableResult
    func ensurePlan(on day: Date) -> DayPlan {
        if let p = plan(on: day) { return p }
        let p = DayPlan(day: calendar.startOfDay(for: day))
        context.insert(p)
        return p
    }

    func isCommitted(_ task: TodoTask, on day: Date) -> Bool {
        plan(on: day)?.committedTaskIDs.contains(task.id) ?? false
    }

    /// 切换 task 在 day 的承诺状态。
    func toggle(_ task: TodoTask, on day: Date) {
        let p = ensurePlan(on: day)
        if let idx = p.committedTaskIDs.firstIndex(of: task.id) {
            p.committedTaskIDs.remove(at: idx)
        } else {
            p.committedTaskIDs.append(task.id)
        }
    }

    /// day 当天承诺的任务(按承诺顺序;已删除的 ID 跳过)。
    func committedTasks(on day: Date) -> [TodoTask] {
        guard let p = plan(on: day) else { return [] }
        let all = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return p.committedTaskIDs.compactMap { byID[$0] }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: PASS（4 tests）

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/PlanStore.swift WorkPanelTests/PlanStoreTests.swift
git commit -m "feat(plan): PlanStore 读写今日承诺 + toggle"
```

---

## Task 3: 跨天触发判定 + lastPlannedDay 偏好键

**Files:**
- Modify: `WorkPanel/Store/PlanStore.swift`（加静态函数）
- Modify: `WorkPanel/Store/AppSettings.swift:11`（加键）
- Test: `WorkPanelTests/PlanStoreTests.swift`（追加）

- [ ] **Step 1: 写失败测试 — needsPlanning 跨天判定**

在 `PlanStoreTests` 追加：

```swift
    @Test func needsPlanningWhenNeverPlanned() {
        #expect(PlanStore.needsPlanning(lastPlanned: nil, now: day, calendar: calendar))
    }

    @Test func needsPlanningWhenLastPlannedYesterday() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        #expect(PlanStore.needsPlanning(lastPlanned: yesterday, now: day, calendar: calendar))
    }

    @Test func noPlanningWhenAlreadyPlannedToday() {
        let earlierToday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7))!
        #expect(!PlanStore.needsPlanning(lastPlanned: earlierToday, now: day, calendar: calendar))
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: 编译失败 / "type 'PlanStore' has no member 'needsPlanning'"

- [ ] **Step 3: 加 needsPlanning 静态函数**

在 `WorkPanel/Store/PlanStore.swift` 的 `PlanStore` 类内追加：

```swift
    /// 是否该触发开工规划:从未规划过,或上次规划不在今天。
    nonisolated static func needsPlanning(lastPlanned: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastPlanned else { return true }
        return !calendar.isDate(lastPlanned, inSameDayAs: now)
    }
```

- [ ] **Step 4: 加 AppSettings 偏好键**

`WorkPanel/Store/AppSettings.swift`，在 `Key` 枚举内（第 11 行 `boardViewMode` 下方）加：

```swift
        static let lastPlannedDay = "lastPlannedDay"   // Double: 上次开工规划日的 timeIntervalSinceReferenceDate
```

- [ ] **Step 5: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStoreTests`
Expected: PASS（7 tests）

- [ ] **Step 6: 提交**

```bash
git add WorkPanel/Store/PlanStore.swift WorkPanel/Store/AppSettings.swift WorkPanelTests/PlanStoreTests.swift
git commit -m "feat(plan): 跨天触发判定 needsPlanning + lastPlannedDay 键"
```

---

## Task 4: PlanStats — 复盘统计纯函数

**Files:**
- Create: `WorkPanel/Store/PlanStats.swift`
- Test: `WorkPanelTests/PlanStatsTests.swift`

口径（全部派生自 `[DayPlan]` + 任务 `completedAt`）：
- **承诺数（某日）** = 那条 DayPlan 的 `committedTaskIDs.count`。
- **完成数（某日）** = 该日承诺任务里 `completedAt` 落在当天的数量。
- **顺延天数（某任务）** = 它被承诺、但当天未完成的天数；≥2 计入顺延榜，按天数倒序。
- **超载日** = `承诺数 − 完成数 ≥ threshold`（默认 3）的天数。

- [ ] **Step 1: 写失败测试 — dayStats / carryOver / overloadDays**

`WorkPanelTests/PlanStatsTests.swift`：

```swift
import Testing
import Foundation
@testable import WorkPanel

struct PlanStatsTests {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private func d(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    // 周一承诺 A、B,只 A 当天完成 → committed 2 / completed 1
    @Test func dayStatsCountsCommittedAndCompletedSameDay() {
        let a = TodoTask(title: "A"); a.isCompleted = true; a.completedAt = d(1, 14)
        let b = TodoTask(title: "B")
        let plan = DayPlan(day: calendar.startOfDay(for: d(1)),
                           committedTaskIDs: [a.id, b.id])
        let stats = PlanStats.dayStats(plans: [plan], tasks: [a, b], calendar: calendar)
        #expect(stats.count == 1)
        #expect(stats[0].committed == 2)
        #expect(stats[0].completed == 1)
    }

    // 任务在周一/周二被承诺都没当天完成 → 顺延 2 天
    @Test func carryOverCountsRepeatedlyCommittedUnfinished() {
        let t = TodoTask(title: "拖延王")
        let p1 = DayPlan(day: calendar.startOfDay(for: d(1)), committedTaskIDs: [t.id])
        let p2 = DayPlan(day: calendar.startOfDay(for: d(2)), committedTaskIDs: [t.id])
        let out = PlanStats.carryOver(plans: [p1, p2], tasks: [t], calendar: calendar)
        #expect(out.count == 1)
        #expect(out[0].task.id == t.id)
        #expect(out[0].days == 2)
    }

    // 只承诺 1 天的不进顺延榜
    @Test func carryOverExcludesSingleDay() {
        let t = TodoTask(title: "一次性")
        let p1 = DayPlan(day: calendar.startOfDay(for: d(1)), committedTaskIDs: [t.id])
        #expect(PlanStats.carryOver(plans: [p1], tasks: [t], calendar: calendar).isEmpty)
    }

    // 承诺 4 完成 1 → 差 3 ≥ 阈值 3 → 超载日 +1
    @Test func overloadDaysCountsHighGap() {
        let tasks = (0..<4).map { TodoTask(title: "T\($0)") }
        tasks[0].isCompleted = true; tasks[0].completedAt = d(1, 15)
        let plan = DayPlan(day: calendar.startOfDay(for: d(1)),
                           committedTaskIDs: tasks.map(\.id))
        let n = PlanStats.overloadDays(plans: [plan], tasks: tasks, threshold: 3, calendar: calendar)
        #expect(n == 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStatsTests`
Expected: 编译失败 / "cannot find 'PlanStats' in scope"

- [ ] **Step 3: 新建 PlanStats**

`WorkPanel/Store/PlanStats.swift`：

```swift
import Foundation

/// 复盘统计:从 [DayPlan] + 任务 completedAt 派生,无副作用、不依赖容器。
enum PlanStats {
    struct DayStat: Equatable {
        let day: Date
        let committed: Int
        let completed: Int
    }

    private static func taskMap(_ tasks: [TodoTask]) -> [UUID: TodoTask] {
        Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// 某日承诺任务里,completedAt 落在该日的数量。
    private static func completedCount(in plan: DayPlan,
                                       map: [UUID: TodoTask],
                                       calendar: Calendar) -> Int {
        plan.committedTaskIDs.reduce(0) { acc, id in
            guard let t = map[id], let done = t.completedAt,
                  calendar.isDate(done, inSameDayAs: plan.day) else { return acc }
            return acc + 1
        }
    }

    /// 每个 DayPlan 一条 DayStat,按 day 升序。
    static func dayStats(plans: [DayPlan], tasks: [TodoTask], calendar: Calendar) -> [DayStat] {
        let map = taskMap(tasks)
        return plans.sorted { $0.day < $1.day }.map { plan in
            DayStat(day: plan.day,
                    committed: plan.committedTaskIDs.count,
                    completed: completedCount(in: plan, map: map, calendar: calendar))
        }
    }

    /// 顺延榜:被承诺、但当天未完成的天数 ≥2 的任务,按天数倒序。
    static func carryOver(plans: [DayPlan], tasks: [TodoTask], calendar: Calendar)
        -> [(task: TodoTask, days: Int)] {
        let map = taskMap(tasks)
        var counts: [UUID: Int] = [:]
        for plan in plans {
            for id in plan.committedTaskIDs {
                let doneToday = map[id]?.completedAt.map { calendar.isDate($0, inSameDayAs: plan.day) } ?? false
                if !doneToday { counts[id, default: 0] += 1 }
            }
        }
        return counts
            .filter { $0.value >= 2 }
            .compactMap { id, n in map[id].map { (task: $0, days: n) } }
            .sorted { $0.days > $1.days }
    }

    /// 超载日:承诺数 − 完成数 ≥ threshold 的天数。
    static func overloadDays(plans: [DayPlan], tasks: [TodoTask],
                             threshold: Int, calendar: Calendar) -> Int {
        let map = taskMap(tasks)
        return plans.reduce(0) { acc, plan in
            let gap = plan.committedTaskIDs.count - completedCount(in: plan, map: map, calendar: calendar)
            return acc + (gap >= threshold ? 1 : 0)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/PlanStatsTests`
Expected: PASS（4 tests）

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Store/PlanStats.swift WorkPanelTests/PlanStatsTests.swift
git commit -m "feat(plan): PlanStats 复盘统计纯函数(承诺/完成/顺延/超载)"
```

---

## Task 5: BoardViewMode 加 review 透镜

**Files:**
- Modify: `WorkPanel/Models/BoardViewMode.swift`
- Test: `WorkPanelTests/BoardViewModeReviewTests.swift`

- [ ] **Step 1: 写失败测试 — review 在 allCases 末尾且有中文 label**

`WorkPanelTests/BoardViewModeReviewTests.swift`：

```swift
import Testing
@testable import WorkPanel

struct BoardViewModeReviewTests {
    @Test func reviewIsLastCaseWithLabel() {
        #expect(BoardViewMode.allCases.last == .review)
        #expect(BoardViewMode.review.label == "复盘")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardViewModeReviewTests`
Expected: 编译失败 / "type 'BoardViewMode' has no member 'review'"

- [ ] **Step 3: 加 review case**

`WorkPanel/Models/BoardViewMode.swift`，把：

```swift
    case kanban, matrix, today, priority
```

改为：

```swift
    case kanban, matrix, today, priority, review
```

并在 `label` 的 switch 内 `case .priority:` 行下方加：

```swift
        case .review:   "复盘"
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/BoardViewModeReviewTests`
Expected: PASS（1 test）

- [ ] **Step 5: 提交**

```bash
git add WorkPanel/Models/BoardViewMode.swift WorkPanelTests/BoardViewModeReviewTests.swift
git commit -m "feat(plan): BoardViewMode 新增 review 透镜"
```

---

## Task 6: PlanningView — 开工规划界面

**Files:**
- Create: `WorkPanel/UI/PlanningView.swift`

说明：纯 UI，手动验证（对齐项目「交互类 UI 用 store 单测覆盖、视图本身手动验证」的习惯）。逻辑已被 Task 2/3 的 PlanStore 单测覆盖。

- [ ] **Step 1: 新建 PlanningView**

`WorkPanel/UI/PlanningView.swift`：

```swift
import SwiftUI
import SwiftData

/// 开工规划:从活动任务里挑出「今日承诺」。逾期+今日到期者置顶高亮作为建议。
/// 不限数量、不拦截(只记录不干预)。确认后写 lastPlannedDay。
struct PlanningView: View {
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @AppStorage(AppSettings.Key.lastPlannedDay) private var lastPlannedDay = 0.0

    private var store: PlanStore { PlanStore(context: context) }
    private var now: Date { .now }

    /// 候选:未完成、未 snooze;逾期/今日到期排前,其余按优先级。
    private var candidates: [TodoTask] {
        let cal = Calendar.current
        return tasks
            .filter { !$0.isCompleted && ($0.snoozedUntil.map { $0 <= now } ?? true) }
            .sorted { lhs, rhs in
                let l = suggested(lhs, cal: cal), r = suggested(rhs, cal: cal)
                if l != r { return l }                       // 建议项在前
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
    }

    private func suggested(_ t: TodoTask, cal: Calendar) -> Bool {
        guard let d = t.deadline else { return false }
        return cal.isDateInToday(d) || d < now
    }

    private var committedCount: Int {
        store.plan(on: now)?.committedTaskIDs.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(candidates) { task in
                        row(task)
                    }
                }
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .padding(12)
            }
            .scrollEdgeFade()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("开工规划")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("已承诺 \(committedCount) 件")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button("开始今天") {
                lastPlannedDay = now.timeIntervalSinceReferenceDate
                try? context.save()
                onDone()
            }
            .buttonStyle(NoirPillButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func row(_ task: TodoTask) -> some View {
        let on = store.isCommitted(task, on: now)
        return Button {
            store.toggle(task, on: now)
            try? context.save()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.accent : Theme.textTertiary)
                Text(task.title)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if suggested(task, cal: .current) {
                    Text("建议")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
```

注意：`Theme.accent` / `Theme.cardFill` / `NoirPillButtonStyle` / `.scrollEdgeFade()` 若命名与现有不符，按 `Theme.swift`、`NoirControls.swift`、`ScrollEdgeFade.swift`、`LensCard.swift` 里的实际命名替换（实现者打开这几个文件确认后再写）。

- [ ] **Step 2: 编译确认通过（无单测，验证可构建）**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/PlanningView.swift
git commit -m "feat(plan): PlanningView 开工规划界面"
```

---

## Task 7: TodayLensView 改造为承诺驱动

**Files:**
- Modify: `WorkPanel/UI/TodayLensView.swift`

说明：把今日透镜从「逾期+今日到期」改为「显示今天 DayPlan 的承诺任务」，头部显示「承诺 X · 完成 Y」，并对今日到期但未承诺者给一句克制提示；空态给开工 CTA。纯 UI，手动验证。

- [ ] **Step 1: 改写 TodayLensView**

`WorkPanel/UI/TodayLensView.swift` 整体替换为：

```swift
import SwiftUI
import SwiftData

/// 今日承诺(承诺驱动):显示今天 DayPlan 里主动挑出的任务。
/// 空态引导开工规划;底部克制提示「今天到期但未纳入」的数量。
struct TodayLensView: View {
    var onPlan: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]

    private var store: PlanStore { PlanStore(context: context) }
    private var now: Date { .now }

    private var committed: [TodoTask] { store.committedTasks(on: now) }
    private var completedCount: Int { committed.filter(\.isCompleted).count }

    /// 今天到期/逾期但不在承诺集里的活动任务数。
    private var dueNotCommittedCount: Int {
        let cal = Calendar.current
        let ids = Set(committed.map(\.id))
        return tasks.filter { t in
            guard !t.isCompleted, !ids.contains(t.id), let d = t.deadline else { return false }
            return cal.isDateInToday(d) || d < now
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if committed.isEmpty {
                    emptyState
                } else {
                    HStack {
                        Text("承诺 \(committed.count) · 完成 \(completedCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("规划今天", action: onPlan)
                            .buttonStyle(NoirPillButtonStyle())
                    }
                    .padding(.horizontal, 4)
                    ForEach(committed) { LensCard(task: $0) }
                    if dueNotCommittedCount > 0 {
                        Text("另有 \(dueNotCommittedCount) 件今天到期未纳入")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .padding(12)
        }
        .scrollEdgeFade()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sunrise")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("还没规划今天")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Button("开工规划", action: onPlan)
                .buttonStyle(NoirPillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}
```

注意：沿用文件原有的 `Theme.*`、`LensCard`、`.scrollEdgeFade()`；`NoirPillButtonStyle` 按 `NoirControls.swift` 实际命名替换。

- [ ] **Step 2: 编译确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED（注意 BoardView 仍以无参方式调用 `TodayLensView()`——`onPlan` 有默认值，可编译；Task 8 再接线）

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/TodayLensView.swift
git commit -m "feat(plan): 今日透镜改为承诺驱动 + 开工 CTA"
```

---

## Task 8: ReviewLensView — 复盘透镜

**Files:**
- Create: `WorkPanel/UI/ReviewLensView.swift`

说明：纯 SwiftUI 画数字/简单条，无图表库。本周（最近 7 天）展示承诺 vs 完成、顺延榜、超载天数。统计逻辑全走 PlanStats（Task 4 已单测）。

- [ ] **Step 1: 新建 ReviewLensView**

`WorkPanel/UI/ReviewLensView.swift`：

```swift
import SwiftUI
import SwiftData

/// 复盘(只读):本周承诺 vs 完成、顺延榜、超载天数。只报事实,不评判。
struct ReviewLensView: View {
    private static let overloadThreshold = 3

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query private var plans: [DayPlan]

    private var calendar: Calendar { .current }
    private var now: Date { .now }

    /// 最近 7 个自然日内的 DayPlan。
    private var weekPlans: [DayPlan] {
        guard let from = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        else { return [] }
        return plans.filter { $0.day >= from }
    }

    private var dayStats: [PlanStats.DayStat] {
        PlanStats.dayStats(plans: weekPlans, tasks: tasks, calendar: calendar)
    }
    private var carryOver: [(task: TodoTask, days: Int)] {
        PlanStats.carryOver(plans: weekPlans, tasks: tasks, calendar: calendar)
    }
    private var overloadDays: Int {
        PlanStats.overloadDays(plans: weekPlans, tasks: tasks,
                               threshold: Self.overloadThreshold, calendar: calendar)
    }

    private var dayFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("本周 · 承诺 vs 完成") {
                    if dayStats.isEmpty {
                        Text("本周还没有规划记录")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    } else {
                        ForEach(dayStats, id: \.day) { s in
                            HStack {
                                Text(dayFormatter.string(from: s.day))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary).frame(width: 44, alignment: .leading)
                                Text("承诺 \(s.committed)").foregroundStyle(Theme.textSecondary)
                                Text("完成 \(s.completed)").foregroundStyle(Theme.accent)
                                Spacer()
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                section("顺延榜") {
                    if carryOver.isEmpty {
                        Text("没有反复顺延的任务")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    } else {
                        ForEach(carryOver, id: \.task.id) { item in
                            HStack {
                                Text(item.task.title).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Spacer()
                                Text("顺延 \(item.days) 天").foregroundStyle(Theme.textTertiary)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                section("超载天数") {
                    Text("\(overloadDays) 天承诺远多于完成")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .scrollEdgeFade()
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
    }
}
```

注意：`Theme.accent` 等按 `Theme.swift` 实际命名替换。

- [ ] **Step 2: 编译确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
git add WorkPanel/UI/ReviewLensView.swift
git commit -m "feat(plan): ReviewLensView 复盘透镜"
```

---

## Task 9: BoardView 接线 — 透镜分发 + 图标 + 开工触发

**Files:**
- Modify: `WorkPanel/UI/BoardView.swift`

说明：把 review 透镜接进 content switch + icon；onAppear 跨天判定触发开工规划（overlay）；今日透镜接 `onPlan` 手动重进。纯 UI，手动验证。

- [ ] **Step 1: 加规划 overlay 状态与触发**

`WorkPanel/UI/BoardView.swift`，在 `@AppStorage(...) private var modeRaw ...` 下方加：

```swift
    @AppStorage(AppSettings.Key.lastPlannedDay) private var lastPlannedDay = 0.0
    @State private var showPlanning = false
```

- [ ] **Step 2: content switch 加 review，并给 today 传 onPlan**

把 `content` 的 switch 改为：

```swift
        switch mode {
        case .kanban:   KanbanLensView()
        case .matrix:   MatrixLensView()
        case .today:    TodayLensView(onPlan: { showPlanning = true })
        case .priority: PriorityLensView()
        case .review:   ReviewLensView()
        }
```

- [ ] **Step 3: icon(for:) 加 review 分支**

把 `icon(for:)` 的 switch 改为（在 `case .priority:` 下方加一行）：

```swift
        case .review:   "chart.bar"
```

- [ ] **Step 4: onAppear 触发开工规划 + overlay 承载 PlanningView**

把 `.onAppear { store.seedDefaultColumnsIfNeeded(); try? context.save() }` 改为：

```swift
        .onAppear {
            store.seedDefaultColumnsIfNeeded(); try? context.save()
            let last = lastPlannedDay == 0 ? nil : Date(timeIntervalSinceReferenceDate: lastPlannedDay)
            if PlanStore.needsPlanning(lastPlanned: last, now: .now, calendar: .current) {
                showPlanning = true
            }
        }
        .overlay {
            if showPlanning {
                PlanningView(onDone: { showPlanning = false })
                    .background(
                        LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            }
        }
```

注意：`Theme.panelTop/panelBottom/panelRadius` 已在本文件 `body` 用过，直接沿用。

- [ ] **Step 5: 编译确认通过**

Run: `xcodebuild build -scheme WorkPanel -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: 手动验证清单**

启动 App，打开看板：
- 首次打开（或跨天后）自动弹出「开工规划」；点几个任务 → 顶部「已承诺 N 件」增长；点「开始今天」→ 关闭。
- 切到「今日」透镜：显示刚承诺的任务 + 「承诺 X · 完成 Y」；勾完一个，完成数 +1。
- 同一天再次打开看板：不再自动弹规划（lastPlannedDay 已是今天）。
- 「今日」透镜点「规划今天」可手动重进。
- 切到「复盘」透镜：看到本周承诺/完成、顺延榜、超载天数。

- [ ] **Step 7: 提交**

```bash
git add WorkPanel/UI/BoardView.swift
git commit -m "feat(plan): BoardView 接线 review 透镜 + 开工规划触发"
```

---

## Self-Review（写计划后自检结论）

- **Spec 覆盖**：DayPlan 模型(T1)、PlanStore 读写+toggle(T2)、跨天触发+lastPlannedDay(T3)、PlanStats 四口径(T4)、review 透镜枚举(T5)、PlanningView 开工流程(T6)、今日透镜承诺驱动+克制提示+空态CTA(T7)、复盘三块(T8)、自动触发+手动重进+透镜接线(T9)。spec 各节均有对应任务。
- **占位符**：无 TBD/TODO；逻辑步骤均含完整代码与命令。UI 任务标注「按 Theme/NoirControls 实际命名替换」属真实落地提醒，非占位。
- **类型一致**：`DayPlan(day:committedTaskIDs:)`、`PlanStore(context:calendar:)`、`PlanStore.needsPlanning(lastPlanned:now:calendar:)`、`PlanStats.dayStats/carryOver/overloadDays`、`PlanStats.DayStat(day:committed:completed:)`、`BoardViewMode.review`、`TodayLensView(onPlan:)`、`PlanningView(onDone:)` 跨任务签名一致。
- **风险提示**：UI 任务里 `Theme.accent/cardFill`、`NoirPillButtonStyle`、`.scrollEdgeFade()` 等命名以现有文件为准，实现者落地前先打开 `Theme.swift`/`NoirControls.swift`/`ScrollEdgeFade.swift`/`LensCard.swift` 核对。
