import SwiftUI

/// 自定义 noir 风格日期 + 时间选择器(用作 popover 内容)。
/// 月历网格选日期、时/分步进器选时间,统一绑定到一个 Date。
/// 取代原生 DatePicker,以贴合 App 暗色风格。
struct NoirDatePicker: View {
    @Binding var date: Date

    private let cal = Calendar.current
    private static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 2), count: 7)

    @State private var visibleMonth: Date   // 当前展示月份的首日

    init(date: Binding<Date>) {
        _date = date
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date.wrappedValue)
        _visibleMonth = State(initialValue: cal.date(from: comps) ?? date.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            monthHeader
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Self.weekdaySymbols, id: \.self) { w in
                    Text(w)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(height: 16)
                }
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
            timeRow
        }
    }

    // MARK: 月份头

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(NoirIconButtonStyle(size: 24))
            Spacer()
            Text(visibleMonth.formatted(.dateTime.year().month()))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(NoirIconButtonStyle(size: 24))
        }
    }

    // MARK: 日期格

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let selected = cal.isDate(day, inSameDayAs: date)
            let today = cal.isDateInToday(day)
            Button { apply(day: day) } label: {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? Color.black.opacity(0.86)
                                              : (today ? Theme.accentText : Theme.textPrimary))
                    .frame(width: 30, height: 30)
                    .background {
                        if selected {
                            Circle().fill(Theme.accent)
                        } else if today {
                            Circle().stroke(Theme.accentStroke, lineWidth: 1)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 30, height: 30)
        }
    }

    // MARK: 时间步进

    private var hour: Int { cal.component(.hour, from: date) }
    private var minute: Int { cal.component(.minute, from: date) }

    private var timeRow: some View {
        HStack(spacing: 8) {
            Text("时间")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            stepper(String(format: "%02d", hour),
                    up: { apply(hour: hour + 1) }, down: { apply(hour: hour - 1) })
            Text(":")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            stepper(String(format: "%02d", minute),
                    up: { apply(minute: minute + 5) }, down: { apply(minute: minute - 5) })
        }
    }

    private func stepper(_ display: String,
                         up: @escaping () -> Void,
                         down: @escaping () -> Void) -> some View {
        VStack(spacing: 1) {
            Button(action: up) { Image(systemName: "chevron.up") }
                .buttonStyle(NoirIconButtonStyle(size: 22))
            Text(display)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34)
            Button(action: down) { Image(systemName: "chevron.down") }
                .buttonStyle(NoirIconButtonStyle(size: 22))
        }
    }

    // MARK: 数据 / 变更

    /// 当前展示月份的格子:前导空格补齐到周日起,末尾补满整周。
    private var monthDays: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: visibleMonth),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: visibleMonth))
        else { return [] }
        let leading = cal.component(.weekday, from: first) - 1   // 周日=1 → 0 个前导空格
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            cells.append(cal.date(byAdding: .day, value: day - 1, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func shiftMonth(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = m
        }
    }

    /// 只改动指定分量,其余保留;时/分越界自动回绕。
    private func apply(day: Date? = nil, hour: Int? = nil, minute: Int? = nil) {
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if let day {
            let d = cal.dateComponents([.year, .month, .day], from: day)
            c.year = d.year; c.month = d.month; c.day = d.day
        }
        if let hour { c.hour = (hour % 24 + 24) % 24 }
        if let minute { c.minute = (minute % 60 + 60) % 60 }
        if let new = cal.date(from: c) { date = new }
    }
}
