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

    @Test func leadTimeBeyondDeadlineSkips() async {
        let mock = MockCenter()
        let scheduler = ReminderScheduler(center: mock)
        let now = Date()
        // 截止 10 分钟后,但提前 15 分钟提醒 → 触发时间已过 → 跳过
        let task = TodoTask(title: "x", deadline: now.addingTimeInterval(600))
        await scheduler.schedule(for: task, now: now, leadMinutes: 15)
        #expect(mock.added.isEmpty)
    }

    @Test func soundDisabledLeavesNilSound() async {
        let mock = MockCenter()
        let scheduler = ReminderScheduler(center: mock)
        let now = Date()
        let task = TodoTask(title: "x", deadline: now.addingTimeInterval(3600))
        await scheduler.schedule(for: task, now: now, soundEnabled: false)
        #expect(mock.added.count == 1)
        #expect(mock.added.first?.content.sound == nil)
    }
}
