import SwiftUI

/// Warm Noir Utility 交互控件:统一的 pill 按钮、图标按钮、分段 tab。
/// 三处(看板 header / 透镜切换 / 编辑器)共用,避免样式漂移。

/// 文字命令按钮。prominent = 主操作(橙色实底);否则次级(surfaceEmphasis + 细描边)。
struct NoirPillButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, prominent: prominent)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.86) : Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(prominent ? Theme.accent : Theme.surfaceEmphasis)
                )
                .overlay {
                    if !prominent {
                        Capsule(style: .continuous).stroke(Theme.stroke, lineWidth: 0.6)
                    }
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// 图标按钮:默认 textTertiary,hover 提亮到 textPrimary,按下轻微缩放。
struct NoirIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration)
    }

    private struct Icon: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// 通用分段 tab:胶囊分组,选中段 surfaceEmphasis + textPrimary,未选 textTertiary。
/// 看板透镜切换与编辑器「编辑/预览」共用。
struct NoirSegmented<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let label: String
        var systemImage: String? = nil
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments) { seg in
                let selected = seg.value == selection
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.06)) { selection = seg.value }
                } label: {
                    HStack(spacing: 5) {
                        if let img = seg.systemImage { Image(systemName: img) }
                        Text(seg.label)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(selected ? Theme.surfaceEmphasis : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Theme.surfaceSubtle))
    }
}
