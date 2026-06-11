import SwiftUI

/// 区间日历:并排两个月,点第一下设开始日、第二下设结束日,中间高亮。
/// 日期按天点选;时间(时:分)由下方步进器调整。绑定到外部可空的 start/end。
struct NoirRangeCalendar: View {
    @Binding var start: Date?
    @Binding var end: Date?

    private let cal = Calendar.current
    @State private var leftMonth: Date

    init(start: Binding<Date?>, end: Binding<Date?>) {
        _start = start
        _end = end
        let cal = Calendar.current
        let anchor = start.wrappedValue ?? end.wrappedValue ?? .now
        let comps = cal.dateComponents([.year, .month], from: anchor)
        _leftMonth = State(initialValue: cal.date(from: comps) ?? anchor)
    }

    private var rightMonth: Date { cal.date(byAdding: .month, value: 1, to: leftMonth)! }

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 16) {
                monthGrid(leftMonth)
                monthGrid(rightMonth)
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
            timeRow(label: "开始", date: $start, defaultHour: 0)
            timeRow(label: "结束", date: $end, defaultHour: 18)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { shiftMonths(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(NoirIconButtonStyle(size: 22))
            Spacer()
            Text(monthTitle(leftMonth))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(monthTitle(rightMonth))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { shiftMonths(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(NoirIconButtonStyle(size: 22))
        }
    }

    private func monthGrid(_ month: Date) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(["日","一","二","三","四","五","六"], id: \.self) { w in
                    Text(w).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(monthDays(of: month).enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 26) }
                }
            }
        }
        .frame(width: 196)
    }

    private func dayCell(_ day: Date) -> some View {
        let d = cal.startOfDay(for: day)
        let isStart = start.map { cal.isDate($0, inSameDayAs: d) } ?? false
        let isEnd = end.map { cal.isDate($0, inSameDayAs: d) } ?? false
        let inRange: Bool = {
            guard let s = start, let e = end else { return false }
            return d >= cal.startOfDay(for: s) && d <= cal.startOfDay(for: e)
        }()
        let endpoint = isStart || isEnd
        let isToday = cal.isDateInToday(day)
        return Button { pick(day) } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 12, weight: endpoint ? .bold : .regular))
                .foregroundStyle(endpoint ? Color.black : (inRange ? Theme.accentText : Theme.textSecondary))
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(
                    endpoint ? Theme.accent
                             : (inRange ? Theme.accentSoft
                                        : (isToday ? Theme.surfaceEmphasis : Color.clear)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func timeRow(label: String, date: Binding<Date?>, defaultHour: Int) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                .frame(width: 32, alignment: .leading)
            if let value = date.wrappedValue {
                let comps = cal.dateComponents([.hour, .minute], from: value)
                let hour = comps.hour ?? 0, minute = comps.minute ?? 0
                stepper(String(format: "%02d", hour),
                        up: { setTime(date, hour: hour + 1, minute: minute) },
                        down: { setTime(date, hour: hour - 1, minute: minute) })
                Text(":").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                stepper(String(format: "%02d", minute),
                        up: { setTime(date, hour: hour, minute: minute + 5) },
                        down: { setTime(date, hour: hour, minute: minute - 5) })
                Spacer()
                Button { date.wrappedValue = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }.buttonStyle(.plain)
            } else {
                Text("点选日期以设置").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                Spacer()
            }
        }
    }

    private func stepper(_ display: String, up: @escaping () -> Void, down: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Button(action: down) { Image(systemName: "minus") }.buttonStyle(NoirIconButtonStyle(size: 20))
            Text(display).font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary).frame(width: 26)
            Button(action: up) { Image(systemName: "plus") }.buttonStyle(NoirIconButtonStyle(size: 20))
        }
    }

    // MARK: 选择逻辑

    private func pick(_ day: Date) {
        let clicked = cal.startOfDay(for: day)
        if start == nil || (start != nil && end != nil) {
            start = combine(clicked, timeFrom: start, defaultHour: 0)
            end = nil
        } else if let s = start {
            if clicked < cal.startOfDay(for: s) {
                start = combine(clicked, timeFrom: start, defaultHour: 0)
            } else {
                end = combine(clicked, timeFrom: end, defaultHour: 18)
            }
        }
    }

    private func combine(_ day: Date, timeFrom existing: Date?, defaultHour: Int) -> Date {
        let h: Int, m: Int
        if let existing {
            let c = cal.dateComponents([.hour, .minute], from: existing)
            h = c.hour ?? defaultHour; m = c.minute ?? 0
        } else { h = defaultHour; m = 0 }
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
    }

    private func setTime(_ binding: Binding<Date?>, hour: Int, minute: Int) {
        guard let cur = binding.wrappedValue else { return }
        let h = (hour % 24 + 24) % 24, m = (minute % 60 + 60) % 60
        binding.wrappedValue = cal.date(bySettingHour: h, minute: m, second: 0, of: cur)
    }

    private func shiftMonths(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: leftMonth) { leftMonth = m }
    }

    private func monthTitle(_ d: Date) -> String { d.formatted(.dateTime.year().month()) }

    private func monthDays(of month: Date) -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let leading = cal.component(.weekday, from: first) - 1
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range { cells.append(cal.date(byAdding: .day, value: day - 1, to: first)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
