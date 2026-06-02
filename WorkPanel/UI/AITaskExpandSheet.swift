import SwiftUI

/// 单任务「梳理拓展」预览:进入即调用 AI,加载时显示 spinner,成功后用 MarkdownPreview
/// 展示结果。「应用」把结果回调给调用方(由其追加到任务备注);「取消」丢弃。
struct AITaskExpandSheet: View {
    let prompt: AIPrompt
    let taskContext: String
    let onApply: (String) -> Void
    let onClose: () -> Void

    @State private var result: String = ""
    @State private var loading = true
    @State private var failed = false
    @State private var runTask: Task<Void, Never>?

    @State private var ai = AIService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.accentText)
                Text(prompt.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            Group {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(maxHeight: .infinity)
                } else if failed {
                    HStack { Spacer()
                        Button("重试") { run() }
                            .buttonStyle(NoirPillButtonStyle())
                        Spacer() }
                        .frame(maxHeight: .infinity)
                } else {
                    // 绑定到 result:用户可在应用前直接勾选/编辑预览内容
                    ScrollView { MarkdownPreview(text: $result).padding(8) }
                }
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
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
                Button("取消") { onClose() }
                    .buttonStyle(NoirPillButtonStyle())
                Button("应用到备注") { onApply(result); onClose() }
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
                    .disabled(loading || failed || result.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 520)
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
        .onKeyPress(.escape) { onClose(); return .handled }
        .task { run() }
    }

    private func run() {
        runTask?.cancel()
        loading = true
        failed = false
        runTask = Task {
            do {
                let text = try await ai.run(systemPrompt: prompt.template, userContext: taskContext)
                guard !Task.isCancelled else { return }
                result = text
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                failed = true
                Notice.show(AIService.message(for: error))
            }
        }
    }
}
