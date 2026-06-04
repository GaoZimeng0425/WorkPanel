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
    @State private var errorMessage = ""
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
                if failed {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.priority(.high))
                        ScrollView {
                            Text(errorMessage.isEmpty ? "生成失败" : errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                        }
                        Button("重试") { run() }
                            .buttonStyle(NoirPillButtonStyle())
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if result.isEmpty {
                    // 尚未收到首个增量:转圈等待
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(maxHeight: .infinity)
                } else {
                    // 流式追加到 result,实时渲染;绑定使用户可在应用前直接勾选/编辑
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
        errorMessage = ""
        result = ""
        runTask = Task {
            do {
                for try await delta in ai.stream(systemPrompt: prompt.template, userContext: taskContext) {
                    if Task.isCancelled { return }
                    result += delta
                }
                if Task.isCancelled { return }
                loading = false
                if result.isEmpty { failed = true; errorMessage = "模型没有返回内容" }
            } catch {
                if Task.isCancelled { return }
                loading = false
                failed = true
                errorMessage = AIService.message(for: error)
            }
        }
    }
}
