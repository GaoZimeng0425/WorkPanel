import SwiftUI

struct CaptureView: View {
    let onSave: (ParsedInput, String) -> Void
    let onCancel: () -> Void

    @State private var input = ""
    @State private var notes = ""
    @FocusState private var focus: Field?

    private enum Field { case title, notes }
    private let parser = InputParser()

    private var parsed: ParsedInput { parser.parse(input, now: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("做什么… 例：写周报 明天17:00 !高 #周报", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .medium))
                .focused($focus, equals: .title)
                .onSubmit(save)

            chips

            Divider()

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("备注 / 具体工作内容")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .focused($focus, equals: .notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 74)
                    .font(.system(size: 14))
            }

            hints
        }
        .padding(18)
        .frame(width: 560)
        .onAppear { focus = .title }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { save(); return .handled }
            return .ignored
        }
    }

    @ViewBuilder private var chips: some View {
        HStack(spacing: 8) {
            if !parsed.title.isEmpty {
                chip(text: parsed.title, system: "text.alignleft", tint: .secondary)
            }
            if let deadline = parsed.deadline {
                chip(text: deadline.formatted(date: .abbreviated, time: .shortened),
                     system: "calendar", tint: .blue)
            }
            chip(text: priorityLabel(parsed.priority), system: "flag.fill", tint: priorityColor(parsed.priority))
            ForEach(parsed.tags, id: \.self) { tag in
                chip(text: tag, system: "number", tint: .green)
            }
            if let rule = parsed.recurrence {
                chip(text: recurrenceLabel(rule), system: "repeat", tint: .purple)
            }
        }
        .font(.system(size: 12))
    }

    private func chip(text: String, system: String, tint: Color) -> some View {
        Label(text, systemImage: system)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
    }

    private var hints: some View {
        HStack(spacing: 16) {
            Text("⌘↩︎ 保存")
            Text("esc 取消")
            Text("⇥ 标题↔备注")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    private func save() {
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(parsed, notes)
        input = ""
        notes = ""
    }

    private func priorityLabel(_ p: Priority) -> String {
        switch p { case .high: "高"; case .medium: "中"; case .low: "低" }
    }
    private func priorityColor(_ p: Priority) -> Color {
        switch p { case .high: .red; case .medium: .orange; case .low: .gray }
    }
    private func recurrenceLabel(_ r: RecurrenceRule) -> String {
        switch r { case .daily: "每天"; case .weekdays: "工作日"; case .weekly: "每周"; case .monthly: "每月" }
    }
}
