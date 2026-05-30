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
