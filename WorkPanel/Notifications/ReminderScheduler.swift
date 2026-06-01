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

    func schedule(for task: TodoTask,
                  now: Date = .now,
                  calendar: Calendar = .current,
                  leadMinutes: Int = AppSettings.reminderLeadMinutes,
                  soundEnabled: Bool = AppSettings.notificationSound) async {
        cancel(for: task)
        guard let deadline = task.deadline, !task.isCompleted else { return }
        let fireDate = deadline.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes.isEmpty ? "任务到期" : task.notes
        content.sound = soundEnabled ? .default : nil

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
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
