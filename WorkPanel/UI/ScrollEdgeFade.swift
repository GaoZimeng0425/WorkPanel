import SwiftUI

/// 给滚动视图加上下边缘的渐变提示:当该方向仍有内容时,边缘浮现一条由实到透的
/// 纯色带(默认淡入外壳黑底 `Theme.panelBottom`),使被遮挡的卡片渐隐过渡。
///
/// 系统的 `scrollEdgeEffectStyle` 仅在滚动内容贴着 bar / safe area 时渲染,在面板内
/// 这种无工具栏的裁剪滚动视图上不可见,故自行实现。
extension View {
    func scrollEdgeFade(height: CGFloat = 22, fade: Color = Theme.panelBottom) -> some View {
        modifier(ScrollEdgeFade(bandHeight: height, fade: fade))
    }
}

private struct ScrollEdgeFade: ViewModifier {
    let bandHeight: CGFloat
    let fade: Color
    @State private var moreAbove = false
    @State private var moreBelow = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Edges.self) { geo in
                let maxOffset = geo.contentSize.height - geo.containerSize.height
                guard maxOffset > 0.5 else { return Edges(above: false, below: false) }
                return Edges(above: geo.contentOffset.y > 0.5,
                             below: geo.contentOffset.y < maxOffset - 0.5)
            } action: { _, edges in
                moreAbove = edges.above
                moreBelow = edges.below
            }
            .overlay(alignment: .top)    { band(top: true).opacity(moreAbove ? 1 : 0) }
            .overlay(alignment: .bottom) { band(top: false).opacity(moreBelow ? 1 : 0) }
            .animation(.easeOut(duration: 0.15), value: moreAbove)
            .animation(.easeOut(duration: 0.15), value: moreBelow)
    }

    private func band(top: Bool) -> some View {
        Rectangle()
            .fill(fade)
            .mask(LinearGradient(colors: [.black, .clear],
                                 startPoint: top ? .top : .bottom,
                                 endPoint: top ? .bottom : .top))
            .frame(height: bandHeight)
            .allowsHitTesting(false)
    }

    private struct Edges: Equatable { var above: Bool; var below: Bool }
}
