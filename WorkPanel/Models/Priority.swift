import Foundation

enum Priority: Int, Codable, CaseIterable, Sendable {
    case low = 0, medium = 1, high = 2
}

enum RecurrenceRule: String, Codable, CaseIterable, Sendable {
    case daily, weekdays, weekly, monthly
}
