import SwiftUI
import SwiftData

/// 看板外壳:标题栏 + 透镜 tab 切换 + 按模式分发到各透镜视图。
struct BoardView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]
    @AppStorage(AppSettings.Key.boardViewMode) private var modeRaw = BoardViewMode.kanban.rawValue

    private var store: BoardStore { BoardStore(context: context) }
    private var mode: BoardViewMode { BoardViewMode(rawValue: modeRaw) ?? .kanban }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)
            content
        }
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
        .onAppear { store.seedDefaultColumnsIfNeeded(); try? context.save() }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .kanban:   KanbanLensView()
        case .matrix:   MatrixLensView()
        case .today:    TodayLensView()
        case .priority: PriorityLensView()
        }
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

            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.borderless)
            Button { onClose() } label: {
                Image(systemName: "chevron.up")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.borderless)
            .help("收起 (esc)")
            .accessibilityLabel("收起")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var lensTabStrip: some View {
        HStack(spacing: 4) {
            ForEach(BoardViewMode.allCases) { m in
                let selected = m.rawValue == modeRaw
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.06)) { modeRaw = m.rawValue }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon(for: m))
                        Text(m.label)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selected ? Theme.surfaceEmphasis : Color.clear)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Theme.surfaceSubtle))
    }

    private func icon(for m: BoardViewMode) -> String {
        switch m {
        case .kanban:   "rectangle.split.3x1"
        case .matrix:   "square.grid.2x2"
        case .today:    "calendar"
        case .priority: "flag"
        }
    }
}
