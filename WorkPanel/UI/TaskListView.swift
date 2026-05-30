import SwiftUI
import SwiftData

struct TaskListView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case today = "今天", upcoming = "即将到期", all = "全部"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TodoTask]

    @State private var segment: Segment = .today
    @State private var tagFilter: String? = nil
    @State private var showArchive = false
    @State private var showSettings = false

    private var store: TodoStore { TodoStore(context: context) }

    private var visibleTasks: [TodoTask] {
        let now = Date.now
        let base: [TodoTask]
        switch segment {
        case .today:    base = TaskFilter.today(tasks, now: now)
        case .upcoming: base = TaskFilter.upcoming(tasks, now: now)
        case .all:      base = TaskFilter.all(tasks)
        }
        guard let tag = tagFilter else { return base }
        return base.filter { $0.tags.contains(tag) }
    }

    private var allTags: [String] {
        Array(Set(tasks.flatMap(\.tags))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showArchive {
                archiveList
            } else {
                taskList
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 440)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var header: some View {
        HStack {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(showArchive)

            Menu {
                Button("全部标签") { tagFilter = nil }
                ForEach(allTags, id: \.self) { tag in
                    Button("#\(tag)") { tagFilter = tag }
                }
            } label: {
                Image(systemName: tagFilter == nil ? "tag" : "tag.fill")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(10)
    }

    private var taskList: some View {
        List(visibleTasks) { task in
            row(task)
        }
        .listStyle(.plain)
        .overlay {
            if visibleTasks.isEmpty {
                ContentUnavailableView("没有任务", systemImage: "checkmark.circle")
            }
        }
    }

    private var archiveList: some View {
        List(TaskFilter.archived(tasks)) { task in
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(task.title).strikethrough().foregroundStyle(.secondary)
                Spacer()
                Button("恢复") { store.reopen(task); try? context.save() }
                    .buttonStyle(.borderless)
            }
        }
        .listStyle(.plain)
    }

    private func row(_ task: TodoTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.complete(task); try? context.save()
            } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.borderless)

            Circle()
                .fill(priorityColor(task.priority))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                HStack(spacing: 8) {
                    if let deadline = task.deadline {
                        Text(deadline.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(deadline < .now ? .red : .secondary)
                    }
                    if let rule = task.recurrence {
                        Label(recurrenceLabel(rule), systemImage: "repeat")
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text("#\(tag)").foregroundStyle(.blue)
                    }
                }
                .font(.system(size: 11))
            }

            Spacer()

            Menu {
                Button("推迟到明天") { snooze(task, days: 1) }
                Button("推迟到下周") { snooze(task, days: 7) }
                Divider()
                Button("删除", role: .destructive) { store.delete(task); try? context.save() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Button {
                showArchive.toggle()
            } label: {
                Label(showArchive ? "返回" : "已完成归档",
                      systemImage: showArchive ? "chevron.left" : "checkmark.circle")
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(10)
    }

    private func snooze(_ task: TodoTask, days: Int) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: .now)!
        store.snooze(task, until: until)
        try? context.save()
    }

    private func priorityColor(_ p: Priority) -> Color {
        switch p { case .high: .red; case .medium: .orange; case .low: .gray }
    }
    private func recurrenceLabel(_ r: RecurrenceRule) -> String {
        switch r { case .daily: "每天"; case .weekdays: "工作日"; case .weekly: "每周"; case .monthly: "每月" }
    }
}
