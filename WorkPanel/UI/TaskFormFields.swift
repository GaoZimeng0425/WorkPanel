import SwiftUI

/// 创建 / 编辑任务共用的字段布局。仅负责字段控件,不做任何持久化。
struct TaskFormFields: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var deadline: Date?
    @Binding var priority: Priority
    @Binding var tags: [String]
    @Binding var recurrence: RecurrenceRule?
    @Binding var columnID: UUID?
    let columns: [BoardColumn]

    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, weight: .medium))

            VStack(alignment: .leading, spacing: 4) {
                Text("备注").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .frame(height: 60)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }

            Toggle("截止时间", isOn: hasDeadline)
            if deadline != nil {
                DatePicker("", selection: deadlineValue,
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }

            Picker("优先级", selection: $priority) {
                ForEach(Priority.allCases, id: \.self) { p in
                    Text(Theme.priorityLabel(p)).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Picker("重复", selection: $recurrence) {
                Text("无").tag(RecurrenceRule?.none)
                ForEach(RecurrenceRule.allCases, id: \.self) { r in
                    Text(Theme.recurrenceLabel(r)).tag(Optional(r))
                }
            }
            .pickerStyle(.menu)

            Picker("状态", selection: $columnID) {
                Text("无状态").tag(UUID?.none)
                ForEach(columns) { col in
                    Text(col.name).tag(Optional(col.id))
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 6) {
                Text("标签").font(.caption).foregroundStyle(.secondary)
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 3) {
                                    Text("#\(tag)")
                                    Button { tags.removeAll { $0 == tag } } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.system(size: 11))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.tag.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.tag)
                            }
                        }
                    }
                }
                TextField("添加标签后回车", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addTags)
            }
        }
    }

    private var hasDeadline: Binding<Bool> {
        Binding(get: { deadline != nil },
                set: { deadline = $0 ? (deadline ?? defaultDeadline()) : nil })
    }
    private var deadlineValue: Binding<Date> {
        Binding(get: { deadline ?? defaultDeadline() },
                set: { deadline = $0 })
    }
    private func defaultDeadline() -> Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private func addTags() {
        let parts = newTag.split { $0 == " " || $0 == "," || $0 == "，" }.map(String.init)
        for p in parts where !p.isEmpty && !tags.contains(p) { tags.append(p) }
        newTag = ""
    }
}
