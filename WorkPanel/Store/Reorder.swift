import Foundation

/// 把 `id` 在 `ids` 中移动到「第 targetIndex 个元素之前」(insert-before),返回新数组。
/// 与 BoardStore.move 的数组语义一致:同列表向下移动时目标索引前移一位;越界 clamp;
/// id 不存在则原样返回。容器追加场景传 targetIndex == ids.count。
/// nonisolated:项目默认 MainActor 隔离,纯函数显式 opt-out 以便测试在非隔离上下文调用。
nonisolated func reorderInsertingBefore(_ ids: [UUID], move id: UUID, before targetIndex: Int) -> [UUID] {
    guard let old = ids.firstIndex(of: id) else { return ids }
    var rest = ids
    rest.remove(at: old)
    var t = targetIndex
    if old < targetIndex { t -= 1 }
    t = max(0, min(t, rest.count))
    rest.insert(id, at: t)
    return rest
}
