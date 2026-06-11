import Foundation
import CoreGraphics

/// 甘特图一行的纯数据键:仅起止两个可空时间,无 SwiftData 依赖,便于单测排序/分区。
struct GanttRow: Equatable, Identifiable {
    let id: UUID
    let start: Date?
    let end: Date?

    nonisolated var effectiveStart: Date? { start ?? end }
    nonisolated var isScheduled: Bool { start != nil || end != nil }
}

/// 甘特图纯几何 / 日期换算。无 SwiftUI、无 TodoTask 依赖,成员 nonisolated 以便在非隔离上下文单测。
struct GanttGeometry: Sendable {
    nonisolated let timelineStart: Date    // 时间轴第 0 天的当天 0 点
    nonisolated let dayWidth: CGFloat
    nonisolated let calendar: Calendar

    nonisolated init(timelineStart: Date, dayWidth: CGFloat, calendar: Calendar = .current) {
        self.calendar = calendar
        self.timelineStart = calendar.startOfDay(for: timelineStart)
        self.dayWidth = dayWidth
    }

    /// 从 timelineStart 起的整天序号(向下取整到天)。
    nonisolated func dayIndex(for date: Date) -> Int {
        calendar.dateComponents([.day], from: timelineStart,
                                to: calendar.startOfDay(for: date)).day ?? 0
    }

    nonisolated func x(for date: Date) -> CGFloat {
        CGFloat(dayIndex(for: date)) * dayWidth
    }

    /// 条的 (x, width)。start/end 皆 nil → 返回 nil(未排期)。
    /// 单边、或 start 当天晚于 end 当天 → 该有效日期当天单格(1 天宽)。
    nonisolated func barFrame(start: Date?, end: Date?) -> (x: CGFloat, width: CGFloat)? {
        switch (start, end) {
        case (nil, nil):
            return nil
        case let (s?, e?):
            if calendar.startOfDay(for: e) >= calendar.startOfDay(for: s) {
                let days = dayIndex(for: e) - dayIndex(for: s) + 1
                return (x(for: s), CGFloat(days) * dayWidth)
            }
            return (x(for: s), dayWidth)        // start 在 end 之后 → 单格
        case let (s?, nil):
            return (x(for: s), dayWidth)
        case let (nil, e?):
            return (x(for: e), dayWidth)
        }
    }

    /// 横向位移换算成整天数(四舍五入)。
    nonisolated func daysDelta(translationX: CGFloat) -> Int {
        Int((translationX / dayWidth).rounded())
    }

    /// 平移:start 与 end 同移 days 天,保持时长(nil 的保持 nil)。
    nonisolated func shifted(start: Date?, end: Date?, byDays days: Int)
        -> (start: Date?, end: Date?) {
        (start.map { calendar.date(byAdding: .day, value: days, to: $0)! },
         end.map { calendar.date(byAdding: .day, value: days, to: $0)! })
    }

    /// 拖左端点改 start;不得越过 end 当天(最小 1 天)。
    nonisolated func resizedStart(start: Date, end: Date?, byDays days: Int) -> Date {
        let moved = calendar.date(byAdding: .day, value: days, to: start)!
        guard let end else { return moved }
        if calendar.startOfDay(for: moved) > calendar.startOfDay(for: end) {
            return clampDay(of: moved, toDayOf: end)
        }
        return moved
    }

    /// 拖右端点改 end;不得早于 start 当天(最小 1 天)。
    nonisolated func resizedEnd(start: Date?, end: Date, byDays days: Int) -> Date {
        let moved = calendar.date(byAdding: .day, value: days, to: end)!
        guard let start else { return moved }
        if calendar.startOfDay(for: moved) < calendar.startOfDay(for: start) {
            return clampDay(of: moved, toDayOf: start)
        }
        return moved
    }

    /// 保留 date 的时刻,只把"年月日"换成 ref 的当天。
    nonisolated private func clampDay(of date: Date, toDayOf ref: Date) -> Date {
        let t = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0,
                             second: t.second ?? 0, of: ref) ?? ref
    }

    /// 排期任务按有效开始升序;未排期(start/end 皆 nil)单列,保持输入顺序。
    nonisolated static func partition(_ rows: [GanttRow])
        -> (scheduled: [GanttRow], unscheduled: [GanttRow]) {
        let scheduled = rows.filter(\.isScheduled)
            // effectiveStart 对 isScheduled 行恒非 nil;?? .distantPast 仅为防御性兜底
            .sorted { ($0.effectiveStart ?? .distantPast) < ($1.effectiveStart ?? .distantPast) }
        let unscheduled = rows.filter { !$0.isScheduled }
        return (scheduled, unscheduled)
    }
}
