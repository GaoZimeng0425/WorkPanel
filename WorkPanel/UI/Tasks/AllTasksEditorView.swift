import SwiftUI
import SwiftData
import MarkdownEngine

/// 全量工作内容编辑器:把所有未完成任务渲染成一份 markdown 文档,⌘↩ 一次性 diff 落库。
/// 仅编辑 标题/备注/状态/优先级(!高 !低)/标签(#x);时间类字段不显示、保存时原样保留。
struct AllTasksEditorView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TodoTask]
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    @State private var text = ""
    @State private var anchors: [WorkDocument.Anchor] = []
    @State private var openSnapshot: [WorkTaskSnapshot] = []
    @State private var loaded = false
    @State private var applyingLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全部工作内容")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            NativeTextViewWrapper(text: $text, configuration: SharedMarkdown.editorConfig, fontSize: 13)
                .frame(minHeight: 240, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surfaceSubtle))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.strokeStrong, lineWidth: 0.7))

            HStack {
                Text("状态分组 · 缩进=备注 · !高/!低 · #标签 · ⌘↩ 保存 · esc 取消")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Button("取消") { onClose() }
                    .buttonStyle(NoirPillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(18)
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
            .stroke(Theme.stroke, lineWidth: 1))
        .preferredColorScheme(.dark)
        .onAppear { load() }
        .onChange(of: text) { old, new in
            guard !applyingLoad else { return }
            let edit = WorkDocument.computeEdit(old: Array(old), new: Array(new))
            anchors = WorkDocument.shift(anchors: anchors, by: edit)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let cols = columns.map { WorkColumn(id: $0.id, name: $0.name) }
        let snaps = allTasks.filter { !$0.isCompleted }.map {
            WorkTaskSnapshot(id: $0.id, title: $0.title, notes: $0.notes, priority: $0.priority,
                             tags: $0.tags, columnID: $0.columnID, boardOrder: $0.boardOrder)
        }
        let r = WorkDocument.serialize(columns: cols, tasks: snaps)
        applyingLoad = true
        text = r.text
        anchors = r.anchors
        applyingLoad = false
        openSnapshot = snaps
    }

    private func save() {
        let cols = columns.map { WorkColumn(id: $0.id, name: $0.name) }
        let blocks = WorkDocument.parse(text: text, columns: cols)
        let changes = WorkDocument.reconcile(blocks: blocks, anchors: anchors, liveTasks: openSnapshot)
        WorkDocApplier(context: context).apply(changes)
        onClose()
    }
}
