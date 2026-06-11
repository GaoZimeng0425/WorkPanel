import Testing
import Foundation
@testable import WorkPanel

@MainActor
struct GanttGeometryTests {
    // 用 UTC + 固定起点,避免本地时区影响断言。
    private func geo(dayWidth: CGFloat = 40) -> GanttGeometry {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)   // 1970-01-01 00:00 UTC
        return GanttGeometry(timelineStart: start, dayWidth: dayWidth, calendar: cal)
    }
    private func day(_ n: Int, hour: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(n * 86400 + hour * 3600))
    }

    @Test func dayIndexAndX() {
        let g = geo()
        #expect(g.dayIndex(for: day(0, hour: 23)) == 0)   // 同一天向下取整
        #expect(g.dayIndex(for: day(3)) == 3)
        #expect(g.x(for: day(3)) == 120)                  // 3 * 40
    }

    @Test func barFrameFullRange() {
        let g = geo()
        let f = g.barFrame(start: day(1), end: day(3))
        #expect(f?.x == 40)
        #expect(f?.width == 120)   // 1..3 含两端 = 3 天 * 40
    }

    @Test func barFrameDeadlineOnlyIsSingleDay() {
        let g = geo()
        let f = g.barFrame(start: nil, end: day(2))
        #expect(f?.x == 80)
        #expect(f?.width == 40)
    }

    @Test func barFrameStartAfterEndCollapsesToStartDay() {
        let g = geo()
        let f = g.barFrame(start: day(5), end: day(2))
        #expect(f?.x == 200)
        #expect(f?.width == 40)
    }

    @Test func barFrameNilWhenUnscheduled() {
        #expect(geo().barFrame(start: nil, end: nil) == nil)
    }

    @Test func daysDeltaRounds() {
        let g = geo(dayWidth: 40)
        #expect(g.daysDelta(translationX: 95) == 2)    // 95/40 = 2.375 → 2
        #expect(g.daysDelta(translationX: -60) == -2)  // -1.5 → -2
    }

    @Test func barFrameStartOnlyIsSingleDay() {
        let g = geo()
        let f = g.barFrame(start: day(3), end: nil)
        #expect(f?.x == 120)
        #expect(f?.width == 40)
    }

    @Test func daysDeltaPositiveHalfRoundsUp() {
        let g = geo(dayWidth: 40)
        #expect(g.daysDelta(translationX: 20) == 1)   // 正好 0.5 天 → 远离零取整 → 1
    }

    @Test func shiftedKeepsDuration() {
        let g = geo()
        let r = g.shifted(start: day(1), end: day(3), byDays: 2)
        #expect(r.start == day(3))
        #expect(r.end == day(5))
    }

    @Test func resizedStartClampsToEndDay() {
        let g = geo()
        // start 推到 end 之后 → 夹到与 end 同一天
        let s = g.resizedStart(start: day(1, hour: 9), end: day(2), byDays: 5)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(cal.isDate(s, inSameDayAs: day(2)))
    }

    @Test func resizedEndClampsToStartDay() {
        let g = geo()
        let e = g.resizedEnd(start: day(3), end: day(4, hour: 9), byDays: -10)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(cal.isDate(e, inSameDayAs: day(3)))
    }

    @Test func partitionSortsScheduledAndIsolatesUnscheduled() {
        let a = GanttRow(id: UUID(), start: day(5), end: day(6))
        let b = GanttRow(id: UUID(), start: nil,    end: day(2))   // 只有 deadline
        let c = GanttRow(id: UUID(), start: nil,    end: nil)      // 未排期
        let (scheduled, unscheduled) = GanttGeometry.partition([a, b, c])
        #expect(scheduled.map(\.id) == [b.id, a.id])   // 按有效开始升序(b 的 deadline 早于 a 的 start)
        #expect(unscheduled.map(\.id) == [c.id])
    }
}
