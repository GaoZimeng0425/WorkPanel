import SwiftUI

/// 设置里的提示词管理:列出已保存 prompt(名字 + 形状标记),支持新增/编辑/删除。
/// 改动即时写回 AIPromptStore。
struct AIPromptListView: View {
    @State private var prompts: [AIPrompt] = AIPromptStore.load()
    @State private var editing: AIPrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prompts) { p in
                HStack(spacing: 8) {
                    Text(p.shape.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.surface, in: Capsule())
                    Text(p.name).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    Button { editing = p } label: {
                        Image(systemName: "pencil").foregroundStyle(Theme.textTertiary)
                    }.buttonStyle(.plain)
                    Button { delete(p) } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.priority(.high))
                    }.buttonStyle(.plain)
                }
                .font(.system(size: 12))
            }
            Button {
                editing = AIPrompt(id: UUID(), name: "", shape: .singleTask, template: "")
            } label: {
                Label("新增提示词", systemImage: "plus")
            }
            .buttonStyle(NoirPillButtonStyle())
        }
        .sheet(item: $editing) { p in
            AIPromptEditor(prompt: p) { saved in
                upsert(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private func upsert(_ p: AIPrompt) {
        if let i = prompts.firstIndex(where: { $0.id == p.id }) {
            prompts[i] = p
        } else {
            prompts.append(p)
        }
        AIPromptStore.save(prompts)
    }

    private func delete(_ p: AIPrompt) {
        prompts.removeAll { $0.id == p.id }
        AIPromptStore.save(prompts)
    }
}

/// 单个 prompt 的编辑表单:名字、形状、模板正文。
private struct AIPromptEditor: View {
    @State private var prompt: AIPrompt
    let onSave: (AIPrompt) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.name.isEmpty ? "新增提示词" : "编辑提示词")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            TextField("名字", text: $prompt.name)
                .textFieldStyle(.roundedBorder)

            Picker("形状", selection: $prompt.shape) {
                ForEach(AIPrompt.Shape.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            TextEditor(text: $prompt.template)
                .font(.system(size: 12))
                .frame(height: 160)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.strokeStrong, lineWidth: 0.7)
                )

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .buttonStyle(NoirPillButtonStyle())
                Button("保存") { onSave(prompt) }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .disabled(prompt.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.template.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
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
    }
}
