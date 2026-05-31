import SwiftUI

/// Warm Noir Utility 复用样式:卡片/列容器底、capsule badge、语义状态点。
/// 仅当某模式重复 ≥2 次才抽到此处,避免过度抽象(见 spec Approach A)。

extension View {
    /// 行/卡片底:surfaceSubtle 填充 + strokeStrong 细描边。
    func noirCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.strokeStrong, lineWidth: 0.7)
                )
        )
    }

    /// 列/象限容器底:安静 surface 填充 + stroke 细描边。
    func noirColumn() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 0.6)
                )
        )
    }

    /// 元数据 capsule:10 bold rounded,tint 前景 + 低透明 tint 底。用于 Text / Label。
    func noirBadge(_ tint: Color) -> some View {
        font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule(style: .continuous))
    }
}

/// 语义状态点;glow 仅给需要强调的状态(如 high 优先级)。
struct StatusDot: View {
    let color: Color
    var glow: Bool = false
    var size: CGFloat = Theme.priorityDotSize

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: glow ? color.opacity(0.5) : .clear, radius: glow ? 4 : 0)
    }
}
