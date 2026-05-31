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
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
        HStack {
            Text("看板").font(.headline)
            Text("\(tasks.filter { !$0.isCompleted }.count) 项")
                .foregroundStyle(.secondary).font(.caption)
            Spacer()
            Picker("透镜", selection: $modeRaw) {
                ForEach(BoardViewMode.allCases) { m in
                    Text(m.label).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            Text("esc 收起").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - 临时占位(Task 11-13 替换为独立文件实现)
struct PriorityLensView: View { var body: some View { Color.clear } }
