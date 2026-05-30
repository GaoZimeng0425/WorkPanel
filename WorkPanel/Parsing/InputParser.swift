import Foundation

struct ParsedInput: Equatable, Sendable {
    nonisolated var title: String = ""
    nonisolated var deadline: Date? = nil
    nonisolated var priority: Priority = .medium
    nonisolated var tags: [String] = []
    nonisolated var recurrence: RecurrenceRule? = nil
}

struct InputParser: Sendable {
    nonisolated var calendar: Calendar

    nonisolated init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    nonisolated private static let priorityMap: [String: Priority] = [
        "!高": .high, "!中": .medium, "!低": .low,
        "!1": .high, "!2": .medium, "!3": .low,
    ]
    // Calendar weekday: Sunday = 1 ... Saturday = 7
    nonisolated private static let weekdayMap: [String: Int] = [
        "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1,
    ]
    nonisolated private static let relativeDayMap: [String: Int] = [
        "今天": 0, "今日": 0, "明天": 1, "明日": 1, "后天": 2, "大后天": 3,
    ]

    nonisolated func parse(_ input: String, now: Date, defaultPriority: Priority = .medium) -> ParsedInput {
        var result = ParsedInput()
        result.priority = defaultPriority
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

    nonisolated private func parseRecurrence(_ token: String, now: Date) -> (RecurrenceRule, DateComponents?)? {
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

    nonisolated private func parseDate(_ token: String, now: Date) -> DateComponents? {
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

    nonisolated private func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
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

    nonisolated private func applyPM(_ hour: Int, _ pmOffset: Int) -> Int {
        guard pmOffset == 12 else { return hour }
        return hour < 12 ? hour + 12 : hour
    }

    nonisolated private func nextWeekday(_ target: Int, from now: Date, nextWeek: Bool) -> DateComponents {
        let today = calendar.component(.weekday, from: now)
        var add = (target - today + 7) % 7
        if nextWeek { add += 7 }
        let d = calendar.date(byAdding: .day, value: add, to: now)!
        return calendar.dateComponents([.year, .month, .day], from: d)
    }
}
