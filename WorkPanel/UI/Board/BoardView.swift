import SwiftUI
import SwiftData

/// 看板外壳:标题栏 + 透镜 tab 切换 + 按模式分发到各透镜视图。
struct BoardView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @AppStorage(AppSettings.Key.boardViewMode) private var modeRaw = BoardViewMode.kanban.rawValue
    @AppStorage(AppSettings.Key.lastPlannedDay) private var lastPlannedDay = 0.0
    @State private var showPlanning = false
    @State private var filter = BoardFilter()
    @State private var showFilter = false

    private var store: BoardStore { BoardStore(context: context) }
    private var mode: BoardViewMode { BoardViewMode(rawValue: modeRaw) ?? .kanban }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header
            if showFilter && mode != .review {
                BoardFilterBar(filter: filter)
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
            content
        }
        .environment(filter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .onAppear {
            store.seedDefaultColumnsIfNeeded()
            TagStore(context: context).seedFromTasksIfNeeded()
            try? context.saveTracking()
            let last = lastPlannedDay == 0 ? nil : Date(timeIntervalSinceReferenceDate: lastPlannedDay)
            if PlanStore.needsPlanning(lastPlanned: last, now: .now, calendar: .current) {
                showPlanning = true
            }
        }
        .overlay {
            if showPlanning {
                PlanningView(onDone: { showPlanning = false })
                    .background(
                        LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            }
        }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .kanban:   KanbanLensView()
        case .matrix:   MatrixLensView()
        case .today:    TodayLensView(onPlan: { showPlanning = true })
        case .priority: PriorityLensView()
        case .review:   ReviewLensView()
        case .gantt:    GanttLensView()
        }
    }

    // 视觉胶囊条;拉伸交互由顶部叠加的 AppKit ResizeHandleView 处理。
    private var resizeHandle: some View {
        Capsule()
            .fill(Theme.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("看板")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(tasks.filter { !$0.isCompleted }.count) 项")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Spacer()
            lensTabStrip
            Spacer()

            if mode != .review {
                Button { showFilter.toggle() } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(filter.isActive ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(NoirIconButtonStyle())
                .help("过滤")
                .accessibilityLabel("过滤")
            }
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(NoirIconButtonStyle())
            .accessibilityLabel("设置")
            Button { onClose() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(NoirIconButtonStyle())
            .help("收起 (esc)")
            .accessibilityLabel("收起")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var lensTabStrip: some View {
        NoirSegmented(
            segments: BoardViewMode.allCases.map {
                .init(value: $0.rawValue, label: $0.label, systemImage: icon(for: $0))
            },
            selection: $modeRaw
        )
    }

    private func icon(for m: BoardViewMode) -> String {
        switch m {
        case .kanban:   "rectangle.split.3x1"
        case .matrix:   "square.grid.2x2"
        case .today:    "calendar"
        case .priority: "flag"
        case .review:   "chart.bar"
        case .gantt:    "chart.bar.xaxis"
        }
    }
}
