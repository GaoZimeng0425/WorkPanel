import SwiftUI
import SwiftData
import MarkdownEngine

/// 创建 / 编辑任务的统一编辑器:单个 markdown 文本域,第一行为标题,其余为备注。
/// 第一行可用自然语言 token(如「明天 !高 #工作」)设置截止/优先级/标签/重复;
/// 编辑态缺省即保留(不通过删 token 清除)。⌘↩ 保存 / esc 取消。
struct TaskEditorView: View {
    enum Mode {
        case create(columnID: UUID?)
        case edit(TodoTask)
    }

    let mode: Mode
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    private var todoStore: TodoStore { TodoStore(context: context) }
    private var boardStore: BoardStore { BoardStore(context: context) }
    private let scheduler = ReminderScheduler()

    @State private var text: String
    @State private var priority: Priority
    @State private var selectedTags: [String]
    @State private var columnID: UUID?
    @State private var showingStatusPicker = false
    @State private var showingDatePicker = false
    @State private var showingExpandMenu = false
    @State private var deadline: Date?
    @State private var expandPrompt: AIPrompt?
    private let base: ParsedInput

    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    @Query private var allTasks: [TodoTask]

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let columnID):
            _text = State(initialValue: "")
            var b = ParsedInput()
            b.priority = AppSettings.defaultPriority
            base = b
            _priority = State(initialValue: AppSettings.defaultPriority)
            _selectedTags = State(initialValue: [])
            _columnID = State(initialValue: columnID)
            _deadline = State(initialValue: nil)
        case .edit(let task):
            _text = State(initialValue: task.notes.isEmpty ? task.title : task.title + "\n" + task.notes)
            var b = ParsedInput()
            b.deadline = task.deadline
            b.priority = task.priority
            b.tags = task.tags
            b.recurrence = task.recurrence
            b.urgencyOverride = task.urgencyOverride
            base = b
            _priority = State(initialValue: task.priority)
            _selectedTags = State(initialValue: task.tags)
            _columnID = State(initialValue: task.columnID)
            _deadline = State(initialValue: task.deadline)
        }
    }

    private var allTags: [String] {
        Array(Set(allTasks.flatMap(\.tags))).sorted()
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var resolved: (fields: ParsedInput, notes: String) {
        CaptureDraft.resolve(text: text, base: base, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isEditing ? "编辑任务" : "新建任务")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if AppSettings.aiConfigured {
                    let singleTaskPrompts = AIPromptStore.load().filter { $0.shape == .singleTask }
                    let titleEmpty = resolved.fields.title.trimmingCharacters(in: .whitespaces).isEmpty
                    if singleTaskPrompts.count == 1, let only = singleTaskPrompts.first {
                        // 单个提示词:直接按钮,点击即触发,不再套一层 Menu。
                        Button { expandPrompt = only } label: { sparklesIcon }
                            .buttonStyle(.plain)
                            .disabled(titleEmpty)
                    } else if !singleTaskPrompts.isEmpty {
                        // 多个提示词:noir 风格 popover(与状态/标签选择一致),不用原生 Menu。
                        Button { showingExpandMenu = true } label: { sparklesIcon }
                            .buttonStyle(.plain)
                            .disabled(titleEmpty)
                            .popover(isPresented: $showingExpandMenu, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(singleTaskPrompts) { p in
                                        expandPromptRow(p.name) { expandPrompt = p }
                                    }
                                }
                                .padding(8)
                                .frame(width: 180)
                                .background(Theme.panelBottom)
                                .preferredColorScheme(.dark)
                            }
                    }
                }
            }

            TokenStrip(fields: resolved.fields)

            // 编辑即样式:所见即所得,无编辑/预览切换。
            NativeTextViewWrapper(text: $text, configuration: markdownConfig, fontSize: 13)
            .frame(height: 220)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.strokeStrong, lineWidth: 0.7)
            )

            controls

            HStack {
                if isEditing {
                    Button { deleteTask() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.priority(.high))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("第一行为标题 · ⌘↩ 保存 · esc 取消")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Spacer()
                Button("取消") { onClose() }
                    .buttonStyle(NoirPillButtonStyle())
                    .keyboardShortcut(.cancelAction)   // esc(原由编辑器内部处理,现移到按钮)
                Button("保存") { save() }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)   // ⌘↩
                    .disabled(resolved.fields.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
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
        .onChange(of: text) { _, newText in
            let firstLine = newText.split(separator: "\n", maxSplits: 1,
                                          omittingEmptySubsequences: false)
                                   .first.map(String.init) ?? ""
            if let parsed = InputParser().parse(firstLine, now: .now,
                                                defaultPriority: priority).deadline {
                deadline = parsed
            }
        }
        .sheet(item: $expandPrompt) { p in
            AITaskExpandSheet(
                prompt: p,
                taskContext: AIContext.renderTask(previewTask()),
                onApply: { appendToNotes($0) },
                onClose: { expandPrompt = nil }
            )
        }
    }

    /// 把 noir 调色板灌进 MarkdownEngine,并收紧默认的字号/标题倍率/内边距。
    private var markdownConfig: MarkdownEditorConfiguration {
        // 正文白色;引擎允许独立着色的部分(标记/链接/行内代码/未勾选复选框/引用条)用橙色。
        // 标题/加粗/项目符号文字绑在 bodyText 上,无法单独着色,故保持白色。
        let orange = NSColor(Theme.accent)
        var theme = MarkdownEditorTheme.default
        theme.bodyText = NSColor(Theme.textPrimary)
        theme.mutedText = orange
        theme.disabledText = NSColor(Theme.textMuted)
        theme.headingMarker = orange
        theme.link = orange
        theme.strikethroughColor = NSColor(Theme.textTertiary)

        var config = MarkdownEditorConfiguration.default
        config.theme = theme
        config.textInsets = TextInsets(horizontal: 14, vertical: 12)   // 文本与卡片边缘留白
        config.headings.fontMultipliers = [1.5, 1.3, 1.15, 1.0, 0.9, 0.8]
        config.overscroll = OverscrollPolicy(percent: 0.1, maxPoints: 40, minPoints: 0)
        config.lists.autoClosePairsEnabled = false   // 别把 `[` 自动补成 `[]`,方便手敲 `- [ ] `
        config.lists.indentPerLevel = 0              // 渲染组件不加缩进,贴左边距
        return config
    }

    private var sparklesIcon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accentText)
    }

    private func expandPromptRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showingExpandMenu = false
        } label: {
            Text(title)
                .lineLimit(1)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlRow("重要程度") {
                NoirSegmented(
                    segments: Priority.allCases.reversed().map {
                        .init(value: $0, label: Theme.priorityLabel($0))
                    },
                    selection: $priority
                )
            }
            controlRow("时间") { deadlineControl }
            controlRow("状态") { statusMenu }
            controlRow("标签") {
                TagPickerField(selected: $selectedTags, existing: allTags)
            }
        }
    }

    private var deadlineBinding: Binding<Date> {
        Binding(get: { deadline ?? defaultDeadline() }, set: { deadline = $0 })
    }

    private func defaultDeadline() -> Date {
        let cal = Calendar.current
        let hour = cal.dateComponents([.year, .month, .day, .hour], from: .now)
        let base = cal.date(from: hour) ?? .now
        return cal.date(byAdding: .hour, value: 1, to: base) ?? .now
    }

    @ViewBuilder
    private var deadlineControl: some View {
        if deadline != nil {
            HStack(spacing: 8) {
                Button { showingDatePicker = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar").font(.system(size: 10))
                        Text(deadlineBinding.wrappedValue.formatted(date: .abbreviated, time: .shortened))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .noirPickerPill()
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingDatePicker, arrowEdge: .bottom) {
                    NoirDatePicker(date: deadlineBinding)
                        .padding(12)
                        .frame(width: 250)
                        .background(Theme.panelBottom)
                        .preferredColorScheme(.dark)
                }
                Button { deadline = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button { deadline = defaultDeadline() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.plus")
                    Text("添加时间")
                }
                .foregroundStyle(Theme.textTertiary)
                .noirPickerPill()
            }
            .buttonStyle(.plain)
        }
    }

    private func controlRow<C: View>(_ label: String,
                                     @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .frame(width: 56, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var currentColumnName: String {
        guard let id = columnID else { return "无" }
        return columns.first { $0.id == id }?.name ?? "无"
    }

    private var statusMenu: some View {
        Button { showingStatusPicker = true } label: {
            HStack(spacing: 4) {
                Text(currentColumnName)
                    .lineLimit(1)
                    .foregroundStyle(columnID == nil ? Theme.textTertiary : Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .noirPickerPill()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingStatusPicker, arrowEdge: .bottom) {
            statusPickerPopover
        }
    }

    private var statusPickerPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            statusPickerRow(title: "无", selected: columnID == nil) {
                columnID = nil
            }
            if !columns.isEmpty {
                Rectangle().fill(Theme.stroke).frame(height: 1)
                    .padding(.vertical, 4)
            }
            ForEach(columns) { col in
                statusPickerRow(title: col.name, selected: columnID == col.id) {
                    columnID = col.id
                }
            }
        }
        .padding(8)
        .frame(width: 180)
        .background(Theme.panelBottom)
        .preferredColorScheme(.dark)
    }

    private func statusPickerRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showingStatusPicker = false
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deleteTask() {
        guard case .edit(let task) = mode else { return }
        scheduler.cancel(for: task)
        context.delete(task)
        try? context.save()
        onClose()
    }

    /// 用编辑器当前内容构造一个临时任务,喂给 AI(包含尚未保存的改动)。
    private func previewTask() -> TodoTask {
        let r = resolved
        let fields = CaptureDraft.applyControls(to: r.fields,
                                                priority: priority,
                                                tags: selectedTags,
                                                deadline: deadline)
        return TodoTask(title: r.fields.title.trimmingCharacters(in: .whitespaces),
                        notes: r.notes,
                        deadline: fields.deadline,
                        priority: fields.priority,
                        tags: fields.tags)
    }

    /// 把 AI 结果作为新的一段备注追加到编辑器文本末尾。
    private func appendToNotes(_ addition: String) {
        let trimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if text.hasSuffix("\n") {
            text += "\n\(trimmed)\n"
        } else {
            text += "\n\n\(trimmed)\n"
        }
    }

    private func save() {
        let r = resolved
        let title = r.fields.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        var fields = CaptureDraft.applyControls(to: r.fields,
                                                priority: priority,
                                                tags: selectedTags,
                                                deadline: deadline)
        fields.title = title

        let task: TodoTask
        switch mode {
        case .create:
            task = todoStore.add(fields, notes: r.notes)
        case .edit(let existing):
            existing.title = title
            existing.notes = r.notes
            existing.deadline = fields.deadline
            existing.priority = fields.priority
            existing.tags = fields.tags
            existing.recurrence = fields.recurrence
            existing.urgencyOverride = fields.urgencyOverride
            task = existing
        }
        boardStore.setColumn(task, to: columnID)
        try? context.save()
        Task { await scheduler.schedule(for: task) }
        onClose()
    }
}

/// 编辑器上方的解析预览条:实时显示从第一行解析出的优先级/截止/标签/重复。
private struct TokenStrip: View {
    let fields: ParsedInput

    var body: some View {
        let chips = chipTexts
        HStack(spacing: 6) {
            ForEach(chips, id: \.self) { c in
                Text(c)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.surface, in: Capsule())
                    .lineLimit(1)
            }
            if chips.isEmpty {
                Text("可在第一行用如「明天 18:00 每周一」补充")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var chipTexts: [String] {
        var out: [String] = []
        if let u = fields.urgencyOverride {
            out.append(u ? "紧急" : "不紧急")
        }
        if let d = fields.deadline {
            out.append(d.formatted(date: .abbreviated, time: .shortened))
        }
        if let r = fields.recurrence {
            out.append(Theme.recurrenceLabel(r))
        }
        return out
    }
}
