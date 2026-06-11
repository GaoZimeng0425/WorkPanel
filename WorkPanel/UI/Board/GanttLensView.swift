import SwiftUI
import SwiftData

/// 甘特透镜:未完成任务按时间范围画成横条,可拖动整条平移、拖端点改时长;
/// 未排期(无起止)任务列在底部,点击打开编辑器。
struct GanttLensView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    private let scheduler = ReminderScheduler()

    private let nameW: CGFloat = 132
    private let rowH: CGFloat = 30
    private let rowGap: CGFloat = 6
    private let headerH: CGFloat = 26
    private let cal = Calendar.current

    @State private var scrollX: CGFloat = 0

    // 未完成任务 → GanttRow,分区
    private var partitioned: (scheduled: [GanttRow], unscheduled: [GanttRow]) {
        let rows = tasks.filter { !$0.isCompleted }
            .map { GanttRow(id: $0.id, start: $0.startDate, end: $0.deadline) }
        return GanttGeometry.partition(rows)
    }

    // 时间轴范围:[firstDay, lastDay],含两端
    private var timelineBounds: (start: Date, days: Int) {
        let scheduled = partitioned.scheduled
        let today = cal.startOfDay(for: .now)
        var minDay = today, maxDay = cal.date(byAdding: .day, value: 13, to: today)!
        for r in scheduled {
            for d in [r.start, r.end].compactMap({ $0 }) {
                let day = cal.startOfDay(for: d)
                if day < minDay { minDay = day }
                if day > maxDay { maxDay = day }
            }
        }
        let days = (cal.dateComponents([.day], from: minDay, to: maxDay).day ?? 0) + 1
        return (minDay, days)
    }

    var body: some View {
        GeometryReader { geo in
            let bounds = timelineBounds
            let dayW = max((geo.size.width - nameW) / 14, 28)
            let contentW = CGFloat(bounds.days) * dayW
            let g = GanttGeometry(timelineStart: bounds.start, dayWidth: dayW, calendar: cal)
            let scheduled = partitioned.scheduled
            let unscheduled = partitioned.unscheduled

            VStack(spacing: 0) {
                header(g: g, days: bounds.days, dayW: dayW, contentW: contentW,
                       viewportW: geo.size.width)
                Rectangle().fill(Theme.stroke).frame(height: 1)

                ScrollView(.vertical, showsIndicators: false) {
                    if scheduled.isEmpty && unscheduled.isEmpty {
                        emptyText("还没有任务")
                            .padding(.vertical, 60)
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            // 冻结名列
                            VStack(spacing: rowGap) {
                                ForEach(scheduled) { nameCell($0) }
                            }
                            .frame(width: nameW, alignment: .leading)

                            // 横向滚动的条网格
                            ScrollView(.horizontal, showsIndicators: true) {
                                ZStack(alignment: .topLeading) {
                                    gridLines(days: bounds.days, dayW: dayW)
                                        .frame(width: contentW)
                                    VStack(spacing: rowGap) {
                                        ForEach(scheduled) { row in
                                            barLane(row, g: g, contentW: contentW)
                                        }
                                    }
                                }
                                .frame(width: contentW, alignment: .topLeading)
                            }
                            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                                scrollX = x
                            }
                        }
                        .padding(.top, rowGap)

                        if !unscheduled.isEmpty {
                            unscheduledSection(unscheduled)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: 头 / 网格

    private func header(g: GanttGeometry, days: Int, dayW: CGFloat,
                        contentW: CGFloat, viewportW: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameW, height: headerH)
            HStack(spacing: 0) {
                ForEach(0..<days, id: \.self) { i in
                    dateLabel(dayOffset: i, base: g.timelineStart)
                        .frame(width: dayW, height: headerH)
                }
            }
            .frame(width: contentW, alignment: .leading)
            .offset(x: -scrollX)
            .frame(width: max(viewportW - nameW, 0), alignment: .leading)
            .clipped()
        }
    }

    private func dateLabel(dayOffset: Int, base: Date) -> some View {
        let date = cal.date(byAdding: .day, value: dayOffset, to: base)!
        let isToday = cal.isDateInToday(date)
        return VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Theme.accentText : Theme.textSecondary)
        }
    }

    private func gridLines(days: Int, dayW: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<days, id: \.self) { i in
                Rectangle()
                    .fill(cal.isDateInToday(cal.date(byAdding: .day, value: i, to: timelineBounds.start)!)
                          ? Theme.accent.opacity(0.06) : Color.clear)
                    .frame(width: dayW)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.stroke.opacity(0.5)).frame(width: 1)
                    }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: 行

    private func nameCell(_ row: GanttRow) -> some View {
        Text(title(for: row.id))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: rowH, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .onTapGesture { openEditor(row.id) }
    }

    private func barLane(_ row: GanttRow, g: GanttGeometry, contentW: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: contentW, height: rowH)
            if let frame = g.barFrame(start: row.start, end: row.end) {
                GanttBar(
                    title: title(for: row.id),
                    color: color(for: row.id),
                    baseX: frame.x,
                    baseWidth: frame.width,
                    dayWidth: g.dayWidth,
                    height: rowH,
                    onMove: { dx in commitMove(row, g: g, translationX: dx) },
                    onResizeLeft: { dx in commitResizeLeft(row, g: g, translationX: dx) },
                    onResizeRight: { dx in commitResizeRight(row, g: g, translationX: dx) },
                    onTap: { openEditor(row.id) }
                )
            }
        }
        .frame(height: rowH)
    }

    private func unscheduledSection(_ rows: [GanttRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("未排期")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 10)
            ForEach(rows) { row in
                Text(title(for: row.id))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(Theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { openEditor(row.id) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyText(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    // MARK: 数据辅助

    private func task(_ id: UUID) -> TodoTask? { tasks.first { $0.id == id } }
    private func title(for id: UUID) -> String { task(id)?.title ?? "" }

    private func color(for id: UUID) -> Color {
        guard let colID = task(id)?.columnID,
              let order = columns.first(where: { $0.id == colID })?.order
        else { return Theme.textTertiary }
        return Theme.columnColor(order: order)
    }

    private func openEditor(_ id: UUID) {
        guard let t = task(id) else { return }
        NotificationCenter.default.post(name: .openTaskEditor, object: TaskEditorView.Mode.edit(t))
    }

    // MARK: 拖拽提交

    private func commitMove(_ row: GanttRow, g: GanttGeometry, translationX: CGFloat) {
        let days = g.daysDelta(translationX: translationX)
        guard days != 0 else { return }
        let r = g.shifted(start: row.start, end: row.end, byDays: days)
        write(row.id, start: r.start, end: r.end)
    }

    private func commitResizeLeft(_ row: GanttRow, g: GanttGeometry, translationX: CGFloat) {
        guard let start = row.start ?? row.end else { return }
        let days = g.daysDelta(translationX: translationX)
        guard days != 0 else { return }
        write(row.id, start: g.resizedStart(start: start, end: row.end, byDays: days), end: row.end)
    }

    private func commitResizeRight(_ row: GanttRow, g: GanttGeometry, translationX: CGFloat) {
        guard let end = row.end ?? row.start else { return }
        let days = g.daysDelta(translationX: translationX)
        guard days != 0 else { return }
        write(row.id, start: row.start, end: g.resizedEnd(start: row.start, end: end, byDays: days))
    }

    private func write(_ id: UUID, start: Date?, end: Date?) {
        guard let t = task(id) else { return }
        let deadlineChanged = t.deadline != end
        t.startDate = start
        t.deadline = end
        try? context.saveTracking()      // 自动打点 modifiedAt
        if deadlineChanged {
            scheduler.cancel(for: t)
            Task { await scheduler.schedule(for: t) }
        }
    }
}

/// 单根任务条:拖条身平移、拖左右端点改时长。落点经回调换算成日期。
private struct GanttBar: View {
    let title: String
    let color: Color
    let baseX: CGFloat
    let baseWidth: CGFloat
    let dayWidth: CGFloat
    let height: CGFloat
    let onMove: (CGFloat) -> Void
    let onResizeLeft: (CGFloat) -> Void
    let onResizeRight: (CGFloat) -> Void
    let onTap: () -> Void

    @State private var moveDX: CGFloat = 0
    @State private var leftDX: CGFloat = 0
    @State private var rightDX: CGFloat = 0

    private let handleW: CGFloat = 8

    var body: some View {
        let x = baseX + moveDX + leftDX
        let w = max(dayWidth, baseWidth - leftDX + rightDX)
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color.opacity(0.85))
            .frame(width: w, height: height - 6)
            .overlay(alignment: .leading) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .overlay(alignment: .leading) { handle(.left) }
            .overlay(alignment: .trailing) { handle(.right) }
            .offset(x: x, y: 3)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { moveDX = $0.translation.width }
                    .onEnded { v in onMove(v.translation.width); moveDX = 0 }
            )
            .onTapGesture { onTap() }
    }

    private enum Edge { case left, right }

    private func handle(_ edge: Edge) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))   // 命中区域,几乎透明
            .frame(width: handleW, height: height - 6)
            .overlay {
                Capsule().fill(Color.white.opacity(0.55)).frame(width: 2, height: (height - 6) * 0.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if edge == .left { leftDX = v.translation.width }
                        else { rightDX = v.translation.width }
                    }
                    .onEnded { v in
                        if edge == .left { onResizeLeft(v.translation.width); leftDX = 0 }
                        else { onResizeRight(v.translation.width); rightDX = 0 }
                    }
            )
    }
}
