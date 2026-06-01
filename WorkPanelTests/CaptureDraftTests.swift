import Testing
import Foundation
@testable import WorkPanel

struct CaptureDraftTests {
    // 固定基准:2026-06-01 10:00,Asia/Shanghai,Gregorian(与 InputParserTests 一致)。
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 0))!
    }
    private func resolve(_ text: String, base: ParsedInput = ParsedInput())
        -> (fields: ParsedInput, notes: String) {
        CaptureDraft.resolve(text: text, base: base, now: now, calendar: calendar)
    }

    @Test func firstLineIsTitleRestIsNotes() {
        let r = resolve("写周报\n## 要点\n- 收集数据")
        #expect(r.fields.title == "写周报")
        #expect(r.notes == "## 要点\n- 收集数据")
    }

    @Test func firstLineTokensParsed() {
        let r = resolve("写周报 明天 !高 #工作")
        #expect(r.fields.title == "写周报")
        #expect(r.fields.priority == .high)
        #expect(r.fields.tags == ["工作"])
        #expect(r.fields.deadline != nil)
    }

    @Test func absenceKeepsBaseValues() {
        var base = ParsedInput()
        base.deadline = now
        base.tags = ["旧"]
        base.priority = .high
        let r = resolve("改标题", base: base)        // 第一行无 token
        #expect(r.fields.title == "改标题")
        #expect(r.fields.deadline == now)            // 保留
        #expect(r.fields.tags == ["旧"])             // 保留
        #expect(r.fields.priority == .high)          // 保留(parse 以 base.priority 为默认)
    }

    @Test func firstLineTagsOverrideBase() {
        var base = ParsedInput()
        base.tags = ["旧"]
        let r = resolve("改标题 #新", base: base)
        #expect(r.fields.tags == ["新"])
    }

    @Test func urgencyTokenSetsOverride() {
        let r = resolve("改标题 !紧急")
        #expect(r.fields.urgencyOverride == true)
    }

    @Test func urgencyAbsenceKeepsBase() {
        var base = ParsedInput()
        base.urgencyOverride = true
        let r = resolve("改标题", base: base)        // 第一行无紧急 token
        #expect(r.fields.urgencyOverride == true)     // 保留
    }

    @Test func emptyTextYieldsEmptyTitleAndNotes() {
        let r = resolve("")
        #expect(r.fields.title == "")
        #expect(r.notes == "")
    }

    @Test func applyControlsOverridesPriorityAndTags() {
        var fields = ParsedInput()
        fields.priority = .low                 // 解析自 token 的值
        fields.tags = ["解析来的"]
        let out = CaptureDraft.applyControls(to: fields, priority: .high, tags: ["工作"], deadline: nil)
        #expect(out.priority == .high)         // 控件为准
        #expect(out.tags == ["工作"])          // 控件为准
    }

    @Test func applyControlsOverridesDeadlineKeepsRecurrenceUrgency() {
        var fields = ParsedInput()
        fields.deadline = now                  // 解析自 token
        fields.recurrence = .weekly
        fields.urgencyOverride = true
        let picked = now.addingTimeInterval(3600)
        let out = CaptureDraft.applyControls(to: fields, priority: .medium, tags: [], deadline: picked)
        #expect(out.deadline == picked)        // 控件为准
        #expect(out.recurrence == .weekly)     // 仍来自 token
        #expect(out.urgencyOverride == true)
        #expect(out.tags == [])                // 控件清空标签
    }

    @Test func applyControlsClearsDeadlineWhenNil() {
        var fields = ParsedInput()
        fields.deadline = now
        let out = CaptureDraft.applyControls(to: fields, priority: .medium, tags: [], deadline: nil)
        #expect(out.deadline == nil)           // 控件清空截止时间
    }
}
