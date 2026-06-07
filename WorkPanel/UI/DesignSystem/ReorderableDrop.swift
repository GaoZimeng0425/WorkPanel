import SwiftUI

/// 列内拖动重排的统一实现(看板列 / 今日承诺 / 开工规划三处共用)。
///
/// 机制:每行上报自己在容器坐标空间里的**竖直中点 Y**;容器级落点按松手 Y 与各行中点算
/// insert-before 序号 = 「中点在落点之上的行数」。判定线落在每行正中:光标越过某行中线
/// 才会移动到它之后,上下方向对称(Trello 式手感)。被拖项自身占位由 store 的
/// `oldOrder < index → −1` 补偿处理(见 reorderInsertingBefore / BoardStore.move)。
///
/// 用单一容器级落点而非每张卡片各自落点:macOS 上嵌在 ScrollView 里的 per-card
/// `dropDestination` 不可靠,落点会穿透到外层、永远追加到末尾(见 [[kanban-reorder-location-drop]])。
/// 落库延迟 0.35s,盖过系统拖拽影像残留(与 DeferredDrop 同理)。

struct RowAnchor: Equatable {
    let id: UUID
    let midY: CGFloat
}

struct RowAnchorsKey: PreferenceKey {
    nonisolated static var defaultValue: [RowAnchor] { [] }
    nonisolated static func reduce(value: inout [RowAnchor], nextValue: () -> [RowAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// 标记一个可重排的行,上报它在 `space` 坐标空间里的底边 Y。`space` 必须与同一容器的
    /// `reorderContainer(space:)` 一致。
    func reorderRow(id: UUID, in space: AnyHashable) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowAnchorsKey.self,
                    value: [RowAnchor(id: id, midY: geo.frame(in: .named(space)).midY)]
                )
            }
        )
    }

    /// 容器级落点:按松手位置算 insert-before 序号后,延迟提交给 `onDrop(payload, index)`。
    /// `onDrop` 自行解析 payload(`task.id.uuidString`)并落库。
    ///
    /// `order` 是当前可见行的 id 顺序;动画由它的变化驱动(`.animation(_:value:)`),
    /// 而非依赖落库变更落在 `withAnimation` 事务里——后者随数据源(@Query 属性 vs DayPlan
    /// 数组)而异,会导致看板有动画、今日/规划没有。绑到可见顺序后三处行为一致。
    func reorderContainer(space: AnyHashable, order: [UUID], onDrop: @escaping (String, Int) -> Void) -> some View {
        modifier(ReorderContainer(space: space, order: order, onDrop: onDrop))
    }
}

private struct ReorderContainer: ViewModifier {
    let space: AnyHashable
    let order: [UUID]
    let onDrop: (String, Int) -> Void
    @State private var anchors: [RowAnchor] = []

    func body(content: Content) -> some View {
        content
            .animation(.easeInOut(duration: 0.18), value: order)
            .coordinateSpace(.named(space))
            .onPreferenceChange(RowAnchorsKey.self) { anchors = $0 }
            .dropDestination(for: String.self) { dropped, location in
                guard let payload = dropped.first else { return false }
                let index = anchors.filter { $0.midY < location.y }.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onDrop(payload, index)
                }
                return true
            }
    }
}
