# WorkPanel TODO App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar macOS app that pops a centered capture panel via a global hotkey to quickly record work TODOs with deadline, priority, tags, and notes; lists/manages them from a menu-bar popover; and reminds before deadlines.

**Architecture:** Menu-bar-only app (`LSUIElement`). Two SwiftUI surfaces: a `NSPanel`-hosted capture panel summoned by a global hotkey, and a `MenuBarExtra(.window)` task list. A pure `InputParser` turns one-line input into structured fields; `TodoStore` owns SwiftData CRUD/recurrence/snooze; `ReminderScheduler` schedules `UserNotifications`. All UI/data work on `@MainActor`; the parser is a pure `Sendable` value type.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, AppKit (`NSPanel`), UserNotifications, ServiceManagement (`SMAppService`), and the `KeyboardShortcuts` SPM package (Sindre Sorhus).

**Spec:** `docs/superpowers/specs/2026-05-30-workpanel-todo-design.md`

---

## File Structure

Source files (dropped into `WorkPanel/`, auto-added to the app target via synchronized groups):

| File | Responsibility |
|---|---|
| `WorkPanel/Models/TodoTask.swift` | `@Model TodoTask`, `Priority`, `RecurrenceRule` |
| `WorkPanel/Parsing/InputParser.swift` | `ParsedInput` + pure parser (tokens → fields) |
| `WorkPanel/Store/TodoStore.swift` | SwiftData CRUD, complete+recurrence, snooze |
| `WorkPanel/Store/TaskFilter.swift` | Today/Upcoming/All/Archived filtering + sort |
| `WorkPanel/Notifications/ReminderScheduler.swift` | Schedule/cancel deadline notifications |
| `WorkPanel/System/LaunchAtLogin.swift` | `SMAppService` wrapper |
| `WorkPanel/System/HotkeyManager.swift` | `KeyboardShortcuts.Name` + registration |
| `WorkPanel/UI/PanelController.swift` | `NSPanel` lifecycle (show/hide/center/focus) |
| `WorkPanel/UI/CaptureView.swift` | Capture panel SwiftUI view |
| `WorkPanel/UI/TaskListView.swift` | Menu-bar list (segments, rows, snooze, archive) |
| `WorkPanel/UI/SettingsView.swift` | Hotkey recorder + launch-at-login toggle |
| `WorkPanel/WorkPanelApp.swift` | App entry: `MenuBarExtra` scene + `AppDelegate` wiring (modified) |

Test files (dropped into `WorkPanelTests/`):

| File | Covers |
|---|---|
| `WorkPanelTests/TodoTaskTests.swift` | Model init + SwiftData persistence |
| `WorkPanelTests/InputParserTests.swift` | All token cases |
| `WorkPanelTests/TodoStoreTests.swift` | CRUD, recurrence, snooze, filters |
| `WorkPanelTests/ReminderSchedulerTests.swift` | Schedule/cancel via mock |

Deleted: `WorkPanel/Item.swift`, `WorkPanel/ContentView.swift` (template files).

**Test command** (used throughout):
```bash
xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel \
  -destination 'platform=macOS' -only-testing:WorkPanelTests 2>&1 | tail -30
```
Filter a single suite by appending the suite name, e.g. `-only-testing:WorkPanelTests/InputParserTests`.

---

## Task 1: Project configuration (Swift 6 + LSUIElement + KeyboardShortcuts package)

**Files:**
- Modify: `WorkPanel.xcodeproj` build settings (via Xcode GUI)

This task has no automated test — verification is a clean build.

- [ ] **Step 1: Set Swift language version to 6 for both targets**

In Xcode: select the project → **WorkPanel** target → Build Settings → search "Swift Language Version" → set to **Swift 6**. Repeat for the **WorkPanelTests** target. (Equivalent: change every `SWIFT_VERSION = 5.0;` to `SWIFT_VERSION = 6.0;` in `WorkPanel.xcodeproj/project.pbxproj`.)

- [ ] **Step 2: Mark the app as a menu-bar agent (no Dock icon)**

In Xcode: **WorkPanel** target → Build Settings → search "Application is Agent" → set **Application is Agent (UIElement)** to **YES**. (Equivalent build setting: `INFOPLIST_KEY_LSUIElement = YES;` under the WorkPanel target's Debug and Release configs.)

- [ ] **Step 3: Add the KeyboardShortcuts package**

In Xcode: **File → Add Package Dependencies…** → enter `https://github.com/sindresorhus/KeyboardShortcuts` → Dependency Rule "Up to Next Major" from `2.0.0` → Add Package → add the **KeyboardShortcuts** library product to the **WorkPanel** target only.

- [ ] **Step 4: Verify the project still builds**

Run:
```bash
xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **` (template code still compiles under Swift 6; package resolves).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: Swift 6, LSUIElement agent, add KeyboardShortcuts package"
```

---

## Task 2: Data model + app scaffolding swap

Replaces the template `Item`/`ContentView` with the real `TodoTask` model and a minimal `MenuBarExtra` scene so the project keeps compiling. The capture panel and list are filled in later.

**Files:**
- Create: `WorkPanel/Models/TodoTask.swift`
- Modify: `WorkPanel/WorkPanelApp.swift`
- Delete: `WorkPanel/Item.swift`, `WorkPanel/ContentView.swift`
- Test: `WorkPanelTests/TodoTaskTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/TodoTaskTests.swift`:
```swift
import Testing
import SwiftData
@testable import WorkPanel

@MainActor
struct TodoTaskTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, configurations: config)
        return ModelContext(container)
    }

    @Test func defaultsAreSane() {
        let task = TodoTask(title: "写周报")
        #expect(task.title == "写周报")
        #expect(task.notes == "")
        #expect(task.priority == .medium)
        #expect(task.deadline == nil)
        #expect(task.tags.isEmpty)
        #expect(task.isCompleted == false)
        #expect(task.recurrence == nil)
    }

    @Test func priorityAndRecurrenceRoundTripThroughStorage() throws {
        let context = try makeContext()
        let task = TodoTask(title: "回邮件", priority: .high,
                            tags: ["客户A"], recurrence: .weekly)
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TodoTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.priority == .high)
        #expect(fetched.first?.recurrence == .weekly)
        #expect(fetched.first?.tags == ["客户A"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoTaskTests 2>&1 | tail -20`
Expected: build fails — `cannot find 'TodoTask' in scope`.

- [ ] **Step 3: Create the model**

Create `WorkPanel/Models/TodoTask.swift`:
```swift
import Foundation
import SwiftData

enum Priority: Int, Codable, CaseIterable, Sendable {
    case low = 0, medium = 1, high = 2
}

enum RecurrenceRule: String, Codable, CaseIterable, Sendable {
    case daily, weekdays, weekly, monthly
}

@Model
final class TodoTask {
    var id: UUID
    var title: String
    var notes: String
    var deadline: Date?
    var priorityRaw: Int
    var tags: [String]
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var snoozedUntil: Date?
    var recurrenceRaw: String?

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    var recurrence: RecurrenceRule? {
        get { recurrenceRaw.flatMap(RecurrenceRule.init(rawValue:)) }
        set { recurrenceRaw = newValue?.rawValue }
    }

    init(title: String,
         notes: String = "",
         deadline: Date? = nil,
         priority: Priority = .medium,
         tags: [String] = [],
         recurrence: RecurrenceRule? = nil,
         createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.deadline = deadline
        self.priorityRaw = priority.rawValue
        self.tags = tags
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = createdAt
        self.snoozedUntil = nil
        self.recurrenceRaw = recurrence?.rawValue
    }
}
```

- [ ] **Step 4: Replace the app scaffolding so the module compiles**

Delete the template files:
```bash
git rm WorkPanel/Item.swift WorkPanel/ContentView.swift
```

Replace `WorkPanel/WorkPanelApp.swift` entirely with:
```swift
import SwiftUI
import SwiftData

enum SharedModel {
    @MainActor static let container: ModelContainer = {
        let schema = Schema([TodoTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

@main
struct WorkPanelApp: App {
    var body: some Scene {
        MenuBarExtra("WorkPanel", systemImage: "checklist") {
            Text("WorkPanel")   // placeholder, replaced in Task 10
                .padding()
                .modelContainer(SharedModel.container)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoTaskTests 2>&1 | tail -20`
Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: TodoTask model; swap template scaffolding for MenuBarExtra"
```

---

## Task 3: InputParser

Pure, deterministic parser. Inject `calendar` and `now` so tests don't depend on wall-clock or weekday-of-today.

**Files:**
- Create: `WorkPanel/Parsing/InputParser.swift`
- Test: `WorkPanelTests/InputParserTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/InputParserTests.swift`:
```swift
import Testing
import Foundation
@testable import WorkPanel

struct InputParserTests {
    // Fixed reference: 2026-06-01 10:00, Asia/Shanghai, Gregorian.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 0))!
    }
    private func parse(_ s: String) -> ParsedInput {
        InputParser(calendar: calendar).parse(s, now: now)
    }

    @Test func plainTitleHasNoMetadata() {
        let r = parse("写周报")
        #expect(r.title == "写周报")
        #expect(r.deadline == nil)
        #expect(r.priority == .medium)
        #expect(r.tags.isEmpty)
        #expect(r.recurrence == nil)
    }

    @Test func priorityTokens() {
        #expect(parse("活儿 !高").priority == .high)
        #expect(parse("活儿 !中").priority == .medium)
        #expect(parse("活儿 !低").priority == .low)
        #expect(parse("活儿 !1").priority == .high)
        #expect(parse("活儿 !3").priority == .low)
    }

    @Test func tagsAreCollectedAndStripped() {
        let r = parse("活儿 #周报 #客户A")
        #expect(r.tags == ["周报", "客户A"])
        #expect(r.title == "活儿")
    }

    @Test func relativeDateDefaultsToSixPM() {
        let r = parse("活儿 明天")
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: r.deadline!)
        #expect(c.day == 2)
        #expect(c.hour == 18)
        #expect(c.minute == 0)
    }

    @Test func timeOnlyUsesToday() {
        let r = parse("活儿 17:00")
        let c = calendar.dateComponents([.day, .hour, .minute], from: r.deadline!)
        #expect(c.day == 1)
        #expect(c.hour == 17)
    }

    @Test func chineseAfternoonTime() {
        let r = parse("活儿 下午3点")
        #expect(calendar.component(.hour, from: r.deadline!) == 15)
    }

    @Test func halfHourClock() {
        let r = parse("活儿 9点半")
        let c = calendar.dateComponents([.hour, .minute], from: r.deadline!)
        #expect(c.hour == 9)
        #expect(c.minute == 30)
    }

    @Test func weekdayResolvesToThatWeekday() {
        let r = parse("活儿 周五")
        #expect(calendar.component(.weekday, from: r.deadline!) == 6) // Friday
    }

    @Test func recurrenceKeywords() {
        #expect(parse("活儿 每天").recurrence == .daily)
        #expect(parse("活儿 工作日").recurrence == .weekdays)
        #expect(parse("活儿 每月").recurrence == .monthly)
        let weekly = parse("活儿 每周一")
        #expect(weekly.recurrence == .weekly)
        #expect(calendar.component(.weekday, from: weekly.deadline!) == 2) // Monday
    }

    @Test func fullCombination() {
        let r = parse("写周报 明天 17:00 !高 #周报")
        #expect(r.title == "写周报")
        #expect(r.priority == .high)
        #expect(r.tags == ["周报"])
        let c = calendar.dateComponents([.day, .hour, .minute], from: r.deadline!)
        #expect(c.day == 2)
        #expect(c.hour == 17)
        #expect(c.minute == 0)
    }

    @Test func unrecognizedTokensStayInTitle() {
        let r = parse("修复 bug-123 在 prod")
        #expect(r.title == "修复 bug-123 在 prod")
        #expect(r.deadline == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/InputParserTests 2>&1 | tail -20`
Expected: build fails — `cannot find 'InputParser' in scope`.

- [ ] **Step 3: Implement the parser**

Create `WorkPanel/Parsing/InputParser.swift`:
```swift
import Foundation

struct ParsedInput: Equatable, Sendable {
    var title: String = ""
    var deadline: Date? = nil
    var priority: Priority = .medium
    var tags: [String] = []
    var recurrence: RecurrenceRule? = nil
}

struct InputParser: Sendable {
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private static let priorityMap: [String: Priority] = [
        "!高": .high, "!中": .medium, "!低": .low,
        "!1": .high, "!2": .medium, "!3": .low,
    ]
    // Calendar weekday: Sunday = 1 ... Saturday = 7
    private static let weekdayMap: [String: Int] = [
        "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1,
    ]
    private static let relativeDayMap: [String: Int] = [
        "今天": 0, "今日": 0, "明天": 1, "明日": 1, "后天": 2, "大后天": 3,
    ]

    func parse(_ input: String, now: Date) -> ParsedInput {
        var result = ParsedInput()
        var titleWords: [String] = []
        var dayComponents: DateComponents? = nil
        var time: (hour: Int, minute: Int)? = nil

        let tokens = input
            .split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
            .map(String.init)

        for token in tokens {
            if let p = Self.priorityMap[token] {
                result.priority = p
            } else if token.hasPrefix("#"), token.count > 1 {
                result.tags.append(String(token.dropFirst()))
            } else if let (rule, day) = parseRecurrence(token, now: now) {
                result.recurrence = rule
                if let day { dayComponents = day }
            } else if let t = parseTime(token) {
                time = t
            } else if let day = parseDate(token, now: now) {
                dayComponents = day
            } else {
                titleWords.append(token)
            }
        }

        if dayComponents != nil || time != nil {
            var comps = dayComponents
                ?? calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = time?.hour ?? 18
            comps.minute = time?.minute ?? 0
            comps.second = 0
            result.deadline = calendar.date(from: comps)
        }
        result.title = titleWords.joined(separator: " ")
        return result
    }

    private func parseRecurrence(_ token: String, now: Date) -> (RecurrenceRule, DateComponents?)? {
        if token == "每天" || token == "每日" { return (.daily, nil) }
        if token == "每月" { return (.monthly, nil) }
        if token == "工作日" || token == "每个工作日" { return (.weekdays, nil) }
        if token.hasPrefix("每周") || token.hasPrefix("每星期") {
            let suffix = String(token.dropFirst(token.hasPrefix("每星期") ? 3 : 2))
            let day = Self.weekdayMap[suffix].map { nextWeekday($0, from: now, nextWeek: false) }
            return (.weekly, day)
        }
        return nil
    }

    private func parseDate(_ token: String, now: Date) -> DateComponents? {
        if let offset = Self.relativeDayMap[token] {
            let d = calendar.date(byAdding: .day, value: offset, to: now)!
            return calendar.dateComponents([.year, .month, .day], from: d)
        }
        if token.hasPrefix("下周") || token.hasPrefix("下星期") {
            let suffix = String(token.dropFirst(token.hasPrefix("下星期") ? 3 : 2))
            if let wd = Self.weekdayMap[suffix] {
                return nextWeekday(wd, from: now, nextWeek: true)
            }
        }
        if token.hasPrefix("周") || token.hasPrefix("星期") {
            let suffix = String(token.dropFirst(token.hasPrefix("星期") ? 2 : 1))
            if let wd = Self.weekdayMap[suffix] {
                return nextWeekday(wd, from: now, nextWeek: false)
            }
        }
        return nil
    }

    private func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
        var t = token
        var pmOffset = 0
        if t.hasPrefix("上午") { t = String(t.dropFirst(2)) }
        else if t.hasPrefix("下午") || t.hasPrefix("晚上") { t = String(t.dropFirst(2)); pmOffset = 12 }
        else if t == "中午" { return (12, 0) }

        if let m = t.wholeMatch(of: /(\d{1,2}):(\d{2})/) {
            let h = Int(m.1)!, min = Int(m.2)!
            guard h < 24, min < 60 else { return nil }
            return (applyPM(h, pmOffset), min)
        }
        if let m = t.wholeMatch(of: /(\d{1,2})点(半|\d{1,2}分?)?/) {
            let h = Int(m.1)!
            var min = 0
            if let rest = m.2 {
                if rest == "半" { min = 30 }
                else { min = Int(rest.replacingOccurrences(of: "分", with: "")) ?? 0 }
            }
            guard h < 24, min < 60 else { return nil }
            return (applyPM(h, pmOffset), min)
        }
        return nil
    }

    private func applyPM(_ hour: Int, _ pmOffset: Int) -> Int {
        guard pmOffset == 12 else { return hour }
        return hour < 12 ? hour + 12 : hour
    }

    private func nextWeekday(_ target: Int, from now: Date, nextWeek: Bool) -> DateComponents {
        let today = calendar.component(.weekday, from: now)
        var add = (target - today + 7) % 7
        if nextWeek { add += 7 }
        let d = calendar.date(byAdding: .day, value: add, to: now)!
        return calendar.dateComponents([.year, .month, .day], from: d)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/InputParserTests 2>&1 | tail -20`
Expected: all 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: InputParser for hybrid quick-capture syntax"
```

---

## Task 4: TodoStore + TaskFilter

**Files:**
- Create: `WorkPanel/Store/TodoStore.swift`
- Create: `WorkPanel/Store/TaskFilter.swift`
- Test: `WorkPanelTests/TodoStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/TodoStoreTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct TodoStoreTests {
    private var calendar = Calendar(identifier: .gregorian)
    private func makeStore() throws -> TodoStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, configurations: config)
        return TodoStore(context: ModelContext(container))
    }

    @Test func addInsertsTask() throws {
        let store = try makeStore()
        var parsed = ParsedInput()
        parsed.title = "写周报"
        parsed.priority = .high
        let task = store.add(parsed, notes: "三个项目进度")
        try store.context.save()
        #expect(task.title == "写周报")
        #expect(task.notes == "三个项目进度")
        #expect(try store.context.fetch(FetchDescriptor<TodoTask>()).count == 1)
    }

    @Test func completeNonRecurringSetsFlags() throws {
        let store = try makeStore()
        let task = TodoTask(title: "活儿")
        store.context.insert(task)
        let now = Date()
        store.complete(task, now: now)
        #expect(task.isCompleted)
        #expect(task.completedAt == now)
        #expect(try store.context.fetch(FetchDescriptor<TodoTask>()).count == 1)
    }

    @Test func completeRecurringSpawnsNextOccurrence() throws {
        let store = try makeStore()
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let task = TodoTask(title: "周会", deadline: deadline, recurrence: .weekly)
        store.context.insert(task)
        store.complete(task, now: Date())

        let all = try store.context.fetch(FetchDescriptor<TodoTask>())
        #expect(all.count == 2)
        let next = all.first { !$0.isCompleted }
        #expect(next != nil)
        let nextDay = calendar.dateComponents([.day], from: next!.deadline!).day
        #expect(nextDay == 8) // +7 days
        #expect(next?.recurrence == .weekly)
    }

    @Test func snoozeSetsDate() throws {
        let store = try makeStore()
        let task = TodoTask(title: "活儿")
        store.context.insert(task)
        let until = Date().addingTimeInterval(86_400)
        store.snooze(task, until: until)
        #expect(task.snoozedUntil == until)
    }

    @Test func todayFilterExcludesCompletedSnoozedAndFuture() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
        let dueToday = TodoTask(title: "今天", deadline: cal.date(byAdding: .hour, value: 2, to: now))
        let dueTomorrow = TodoTask(title: "明天", deadline: cal.date(byAdding: .day, value: 1, to: now))
        let done = TodoTask(title: "已完成", deadline: now); done.isCompleted = true
        let snoozed = TodoTask(title: "推迟", deadline: now)
        snoozed.snoozedUntil = cal.date(byAdding: .day, value: 1, to: now)

        let today = TaskFilter.today([dueToday, dueTomorrow, done, snoozed], now: now, calendar: cal)
        #expect(today.map(\.title) == ["今天"])
    }

    @Test func sortRanksHighPriorityThenEarlierDeadline() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
        let lowEarly = TodoTask(title: "低早", deadline: now, priority: .low)
        let highLate = TodoTask(title: "高晚",
                                deadline: cal.date(byAdding: .day, value: 1, to: now),
                                priority: .high)
        let sorted = TaskFilter.all([lowEarly, highLate])
        #expect(sorted.map(\.title) == ["高晚", "低早"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoStoreTests 2>&1 | tail -20`
Expected: build fails — `cannot find 'TodoStore' in scope`.

- [ ] **Step 3: Implement TodoStore**

Create `WorkPanel/Store/TodoStore.swift`:
```swift
import Foundation
import SwiftData

@MainActor
final class TodoStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func add(_ parsed: ParsedInput, notes: String, now: Date = .now) -> TodoTask {
        let task = TodoTask(title: parsed.title,
                            notes: notes,
                            deadline: parsed.deadline,
                            priority: parsed.priority,
                            tags: parsed.tags,
                            recurrence: parsed.recurrence,
                            createdAt: now)
        context.insert(task)
        return task
    }

    func complete(_ task: TodoTask, now: Date = .now, calendar: Calendar = .current) {
        if let rule = task.recurrence,
           let next = Self.nextDeadline(after: task.deadline ?? now, rule: rule, calendar: calendar) {
            let follow = TodoTask(title: task.title,
                                  notes: task.notes,
                                  deadline: next,
                                  priority: task.priority,
                                  tags: task.tags,
                                  recurrence: rule,
                                  createdAt: now)
            context.insert(follow)
        }
        task.isCompleted = true
        task.completedAt = now
    }

    func reopen(_ task: TodoTask) {
        task.isCompleted = false
        task.completedAt = nil
    }

    func snooze(_ task: TodoTask, until date: Date) {
        task.snoozedUntil = date
    }

    func delete(_ task: TodoTask) {
        context.delete(task)
    }

    static func nextDeadline(after date: Date, rule: RecurrenceRule, calendar: Calendar) -> Date? {
        switch rule {
        case .daily:   return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:  return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date)!
            var wd = calendar.component(.weekday, from: d)
            while wd == 1 || wd == 7 { // skip Sunday/Saturday
                d = calendar.date(byAdding: .day, value: 1, to: d)!
                wd = calendar.component(.weekday, from: d)
            }
            return d
        }
    }
}
```

- [ ] **Step 4: Implement TaskFilter**

Create `WorkPanel/Store/TaskFilter.swift`:
```swift
import Foundation

enum TaskFilter {
    static func today(_ tasks: [TodoTask], now: Date, calendar: Calendar = .current) -> [TodoTask] {
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        return tasks
            .filter { task in
                !task.isCompleted
                && (task.snoozedUntil.map { $0 <= now } ?? true)
                && (task.deadline.map { $0 <= endOfToday } ?? false)
            }
            .sorted(by: sortRule)
    }

    static func upcoming(_ tasks: [TodoTask], now: Date, calendar: Calendar = .current) -> [TodoTask] {
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        return tasks
            .filter { !$0.isCompleted && ($0.deadline.map { $0 > endOfToday } ?? false) }
            .sorted(by: sortRule)
    }

    static func all(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { !$0.isCompleted }.sorted(by: sortRule)
    }

    static func archived(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    static func sortRule(_ a: TodoTask, _ b: TodoTask) -> Bool {
        if a.priority.rawValue != b.priority.rawValue {
            return a.priority.rawValue > b.priority.rawValue
        }
        switch (a.deadline, b.deadline) {
        case let (x?, y?): return x < y
        case (nil, _?):    return false
        case (_?, nil):    return true
        case (nil, nil):   return a.createdAt < b.createdAt
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/TodoStoreTests 2>&1 | tail -20`
Expected: all 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: TodoStore (CRUD/recurrence/snooze) and TaskFilter"
```

---

## Task 5: ReminderScheduler

Inject a `NotificationScheduling` protocol so scheduling logic is testable without the real notification center.

**Files:**
- Create: `WorkPanel/Notifications/ReminderScheduler.swift`
- Test: `WorkPanelTests/ReminderSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WorkPanelTests/ReminderSchedulerTests.swift`:
```swift
import Testing
import Foundation
import UserNotifications
@testable import WorkPanel

@MainActor
struct ReminderSchedulerTests {
    final class MockCenter: NotificationScheduling, @unchecked Sendable {
        var added: [UNNotificationRequest] = []
        var removed: [String] = []
        func add(_ request: UNNotificationRequest) async throws { added.append(request) }
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            removed.append(contentsOf: identifiers)
        }
    }

    @Test func schedulesFutureDeadline() async {
        let mock = MockCenter()
        let scheduler = ReminderScheduler(center: mock)
        let task = TodoTask(title: "写周报", deadline: Date().addingTimeInterval(3600))
        await scheduler.schedule(for: task, now: Date())
        #expect(mock.added.count == 1)
        #expect(mock.added.first?.identifier == task.id.uuidString)
        #expect(mock.added.first?.content.title == "写周报")
    }

    @Test func skipsCompletedOrPastOrNoDeadline() async {
        let mock = MockCenter()
        let scheduler = ReminderScheduler(center: mock)
        let now = Date()

        let noDeadline = TodoTask(title: "无截止")
        await scheduler.schedule(for: noDeadline, now: now)

        let past = TodoTask(title: "过期", deadline: now.addingTimeInterval(-3600))
        await scheduler.schedule(for: past, now: now)

        let completed = TodoTask(title: "已完成", deadline: now.addingTimeInterval(3600))
        completed.isCompleted = true
        await scheduler.schedule(for: completed, now: now)

        #expect(mock.added.isEmpty)
    }

    @Test func cancelRemovesByIdentifier() {
        let mock = MockCenter()
        let scheduler = ReminderScheduler(center: mock)
        let task = TodoTask(title: "活儿")
        scheduler.cancel(for: task)
        #expect(mock.removed == [task.id.uuidString])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ReminderSchedulerTests 2>&1 | tail -20`
Expected: build fails — `cannot find 'ReminderScheduler' in scope`.

- [ ] **Step 3: Implement the scheduler**

Create `WorkPanel/Notifications/ReminderScheduler.swift`:
```swift
import Foundation
import UserNotifications

protocol NotificationScheduling {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {}

@MainActor
final class ReminderScheduler {
    private let center: NotificationScheduling

    init(center: NotificationScheduling = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(for task: TodoTask, now: Date = .now, calendar: Calendar = .current) async {
        cancel(for: task)
        guard let deadline = task.deadline, !task.isCompleted, deadline > now else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes.isEmpty ? "任务到期" : task.notes
        content.sound = .default

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: deadline)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString,
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    func cancel(for task: TodoTask) {
        center.removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests/ReminderSchedulerTests 2>&1 | tail -20`
Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: ReminderScheduler with injectable notification center"
```

---

## Task 6: LaunchAtLogin

Thin `SMAppService` wrapper. No automated test (depends on a registered login item); verify it compiles.

**Files:**
- Create: `WorkPanel/System/LaunchAtLogin.swift`

- [ ] **Step 1: Implement the wrapper**

Create `WorkPanel/System/LaunchAtLogin.swift`:
```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: LaunchAtLogin via SMAppService"
```

---

## Task 7: PanelController

AppKit `NSPanel` lifecycle for the capture panel. No automated test (UI/AppKit); verify build, then full manual verification happens in Task 12.

**Files:**
- Create: `WorkPanel/UI/PanelController.swift`

- [ ] **Step 1: Implement the controller**

Create `WorkPanel/UI/PanelController.swift`:
```swift
import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show<Content: View>(@ViewBuilder _ content: () -> Content) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content())
        positionCentered(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle<Content: View>(@ViewBuilder _ content: () -> Content) {
        if isVisible { hide() } else { show(content) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        return panel
    }

    private func positionCentered(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 + visible.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // Auto-dismiss when the panel loses focus.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: PanelController for the floating capture NSPanel"
```

---

## Task 8: HotkeyManager

Defines the global shortcut (`KeyboardShortcuts.Name`) with a default of ⌘⌥J and a registration helper.

**Files:**
- Create: `WorkPanel/System/HotkeyManager.swift`

- [ ] **Step 1: Implement the manager**

Create `WorkPanel/System/HotkeyManager.swift`:
```swift
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleCapture = Self(
        "toggleCapture",
        default: .init(.j, modifiers: [.command, .option])
    )
}

@MainActor
enum HotkeyManager {
    static func register(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleCapture, action: handler)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: HotkeyManager + toggleCapture global shortcut (default ⌘⌥J)"
```

---

## Task 9: CaptureView

The capture panel SwiftUI view: title line with live parse chips, notes editor, keyboard handling. No automated test; verify build, full manual verification in Task 12.

**Files:**
- Create: `WorkPanel/UI/CaptureView.swift`

- [ ] **Step 1: Implement the view**

Create `WorkPanel/UI/CaptureView.swift`:
```swift
import SwiftUI

struct CaptureView: View {
    let onSave: (ParsedInput, String) -> Void
    let onCancel: () -> Void

    @State private var input = ""
    @State private var notes = ""
    @FocusState private var focus: Field?

    private enum Field { case title, notes }
    private let parser = InputParser()

    private var parsed: ParsedInput { parser.parse(input, now: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("做什么… 例：写周报 明天17:00 !高 #周报", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .medium))
                .focused($focus, equals: .title)
                .onSubmit(save)

            chips

            Divider()

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("备注 / 具体工作内容")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .focused($focus, equals: .notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 74)
                    .font(.system(size: 14))
            }

            hints
        }
        .padding(18)
        .frame(width: 560)
        .onAppear { focus = .title }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { save(); return .handled }
            return .ignored
        }
    }

    @ViewBuilder private var chips: some View {
        HStack(spacing: 8) {
            if !parsed.title.isEmpty {
                chip(text: parsed.title, system: "text.alignleft", tint: .secondary)
            }
            if let deadline = parsed.deadline {
                chip(text: deadline.formatted(date: .abbreviated, time: .shortened),
                     system: "calendar", tint: .blue)
            }
            chip(text: priorityLabel(parsed.priority), system: "flag.fill", tint: priorityColor(parsed.priority))
            ForEach(parsed.tags, id: \.self) { tag in
                chip(text: tag, system: "number", tint: .green)
            }
            if let rule = parsed.recurrence {
                chip(text: recurrenceLabel(rule), system: "repeat", tint: .purple)
            }
        }
        .font(.system(size: 12))
    }

    private func chip(text: String, system: String, tint: Color) -> some View {
        Label(text, systemImage: system)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
    }

    private var hints: some View {
        HStack(spacing: 16) {
            Text("⌘↩︎ 保存")
            Text("esc 取消")
            Text("⇥ 标题↔备注")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    private func save() {
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(parsed, notes)
        input = ""
        notes = ""
    }

    private func priorityLabel(_ p: Priority) -> String {
        switch p { case .high: "高"; case .medium: "中"; case .low: "低" }
    }
    private func priorityColor(_ p: Priority) -> Color {
        switch p { case .high: .red; case .medium: .orange; case .low: .gray }
    }
    private func recurrenceLabel(_ r: RecurrenceRule) -> String {
        switch r { case .daily: "每天"; case .weekdays: "工作日"; case .weekly: "每周"; case .monthly: "每月" }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: CaptureView with live parse chips and notes"
```

---

## Task 10: TaskListView

The menu-bar popover: segment switch, task rows with complete/snooze/delete, tag filter, archive view. No automated test; verify build, full manual verification in Task 12.

**Files:**
- Create: `WorkPanel/UI/TaskListView.swift`

- [ ] **Step 1: Implement the view**

Create `WorkPanel/UI/TaskListView.swift`:
```swift
import SwiftUI
import SwiftData

struct TaskListView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case today = "今天", upcoming = "即将到期", all = "全部"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]

    @State private var segment: Segment = .today
    @State private var tagFilter: String? = nil
    @State private var showArchive = false
    @State private var showSettings = false

    private var store: TodoStore { TodoStore(context: context) }

    private var visibleTasks: [TodoTask] {
        let now = Date.now
        let base: [TodoTask]
        switch segment {
        case .today:    base = TaskFilter.today(tasks, now: now)
        case .upcoming: base = TaskFilter.upcoming(tasks, now: now)
        case .all:      base = TaskFilter.all(tasks)
        }
        guard let tag = tagFilter else { return base }
        return base.filter { $0.tags.contains(tag) }
    }

    private var allTags: [String] {
        Array(Set(tasks.flatMap(\.tags))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showArchive {
                archiveList
            } else {
                taskList
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 440)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var header: some View {
        HStack {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(showArchive)

            Menu {
                Button("全部标签") { tagFilter = nil }
                ForEach(allTags, id: \.self) { tag in
                    Button("#\(tag)") { tagFilter = tag }
                }
            } label: {
                Image(systemName: tagFilter == nil ? "tag" : "tag.fill")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(10)
    }

    private var taskList: some View {
        List(visibleTasks) { task in
            row(task)
        }
        .listStyle(.plain)
        .overlay {
            if visibleTasks.isEmpty {
                ContentUnavailableView("没有任务", systemImage: "checkmark.circle")
            }
        }
    }

    private var archiveList: some View {
        List(TaskFilter.archived(tasks)) { task in
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(task.title).strikethrough().foregroundStyle(.secondary)
                Spacer()
                Button("恢复") { store.reopen(task); try? context.save() }
                    .buttonStyle(.borderless)
            }
        }
        .listStyle(.plain)
    }

    private func row(_ task: TodoTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.complete(task); try? context.save()
            } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.borderless)

            Circle()
                .fill(priorityColor(task.priority))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                HStack(spacing: 8) {
                    if let deadline = task.deadline {
                        Text(deadline.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(deadline < .now ? .red : .secondary)
                    }
                    if let rule = task.recurrence {
                        Label(recurrenceLabel(rule), systemImage: "repeat")
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text("#\(tag)").foregroundStyle(.blue)
                    }
                }
                .font(.system(size: 11))
            }

            Spacer()

            Menu {
                Button("推迟到明天") { snooze(task, days: 1) }
                Button("推迟到下周") { snooze(task, days: 7) }
                Divider()
                Button("删除", role: .destructive) { store.delete(task); try? context.save() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Button {
                showArchive.toggle()
            } label: {
                Label(showArchive ? "返回" : "已完成归档",
                      systemImage: showArchive ? "chevron.left" : "checkmark.circle")
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(10)
    }

    private func snooze(_ task: TodoTask, days: Int) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: .now)!
        store.snooze(task, until: until)
        try? context.save()
    }

    private func priorityColor(_ p: Priority) -> Color {
        switch p { case .high: .red; case .medium: .orange; case .low: .gray }
    }
    private func recurrenceLabel(_ r: RecurrenceRule) -> String {
        switch r { case .daily: "每天"; case .weekdays: "工作日"; case .weekly: "每周"; case .monthly: "每月" }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -10`
Expected: build fails — `cannot find 'SettingsView' in scope` (created in Task 11). This is expected; proceed to Task 11 before re-verifying.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: TaskListView (segments, rows, snooze, archive)"
```

---

## Task 11: SettingsView

Hotkey recorder + launch-at-login toggle.

**Files:**
- Create: `WorkPanel/UI/SettingsView.swift`

- [ ] **Step 1: Implement the view**

Create `WorkPanel/UI/SettingsView.swift`:
```swift
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置").font(.headline)

            Form {
                KeyboardShortcuts.Recorder("唤起捕获面板：", name: .toggleCapture)
                Toggle("开机自启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do { try LaunchAtLogin.setEnabled(enabled) }
                        catch { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **` (Task 10's missing-symbol error is now resolved).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: SettingsView (hotkey recorder + launch at login)"
```

---

## Task 12: Final wiring + end-to-end verification

Connects the global hotkey → capture panel → store → scheduler, and points the `MenuBarExtra` at the real list. No automated test; this task is verified by running the app.

**Files:**
- Modify: `WorkPanel/WorkPanelApp.swift`

- [ ] **Step 1: Wire everything in the App entry**

Replace `WorkPanel/WorkPanelApp.swift` entirely with:
```swift
import SwiftUI
import SwiftData

enum SharedModel {
    @MainActor static let container: ModelContainer = {
        let schema = Schema([TodoTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

@main
struct WorkPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("WorkPanel", systemImage: "checklist") {
            TaskListView()
                .modelContainer(SharedModel.container)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = PanelController()
    private let scheduler = ReminderScheduler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.register { [weak self] in self?.toggleCapture() }
        Task { _ = await scheduler.requestAuthorization() }
    }

    private func toggleCapture() {
        if panel.isVisible { panel.hide(); return }
        let context = ModelContext(SharedModel.container)
        let store = TodoStore(context: context)
        panel.show {
            CaptureView(
                onSave: { [weak self] parsed, notes in
                    let task = store.add(parsed, notes: notes)
                    try? context.save()
                    let scheduler = self?.scheduler
                    Task { await scheduler?.schedule(for: task) }
                    self?.panel.hide()
                },
                onCancel: { [weak self] in self?.panel.hide() }
            )
        }
    }
}
```

- [ ] **Step 2: Verify the full build and the whole test suite**

Run:
```bash
xcodebuild test -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' -only-testing:WorkPanelTests 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` — all suites (TodoTask, InputParser, TodoStore, ReminderScheduler) pass.

- [ ] **Step 3: Manual end-to-end verification**

Launch the app:
```bash
xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/WorkPanel-*/Build/Products/Debug/WorkPanel.app
```
Verify each:
- [ ] No Dock icon appears; a checklist icon appears in the menu bar.
- [ ] Pressing ⌘⌥J shows the centered capture panel; the title field is focused.
- [ ] Typing `写周报 明天17:00 !高 #周报` shows live chips (deadline / 高 / 周报).
- [ ] ⌘↩ saves and the panel closes; `esc` cancels.
- [ ] Clicking the menu-bar icon shows the task in 今天/全部; priority dot is red; tag and time show.
- [ ] The complete button moves it to 已完成归档; 恢复 brings it back.
- [ ] The `⋯` menu can 推迟到明天 (task leaves 今天) and 删除.
- [ ] Settings: the hotkey recorder rebinds the shortcut; the 开机自启动 toggle persists.
- [ ] First run prompts for notification permission; a task with a near-future deadline fires a notification.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire hotkey/panel/store/scheduler; real MenuBarExtra list"
```

---

## Self-Review Notes

- **Spec coverage:** hotkey (Task 8/12) · capture panel (7/9) · hybrid parse incl. `!`/`#`/dates/times/recurrence (3) · fields title/notes/deadline/priority/tags/recurrence/snooze (2) · menu-bar list with 今天/即将/全部 + tag filter + archive (10) · reminders (5/12) · recurrence generation (4) · snooze (4/10) · launch-at-login (6/11) · local SwiftData (2) · Swift 6 strict concurrency + LSUIElement (1). All spec sections map to a task.
- **Deviation from spec (intentional):** `TodoTask` gains a `var id: UUID` not listed in the spec — required as a stable notification identifier (Task 5). `priority`/`recurrence` are stored as `priorityRaw: Int` / `recurrenceRaw: String?` with computed accessors so priority is directly sortable; the public API matches the spec's `Priority`/`RecurrenceRule`.
- **Type consistency:** `ParsedInput`, `TodoTask.init(...)`, `TodoStore.add/complete/snooze/reopen/delete`, `TaskFilter.today/upcoming/all/archived/sortRule`, `ReminderScheduler.schedule/cancel`, and `KeyboardShortcuts.Name.toggleCapture` are referenced with identical signatures across tasks.
