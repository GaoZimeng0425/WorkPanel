import SwiftUI

/// 接收字符串载荷的拖拽落点,把数据改动推迟到系统拖拽影像淡出之后(~0.35s)再带动画执行。
///
/// macOS 的系统拖拽影像在松手后会在光标处原地淡出约 0.3s(不像 iOS 会吸入目标),
/// 而 SwiftData 的 `@Query` 让真实视图瞬间落位,两者在该窗口内重叠 = 光标处残留。
/// 推迟落位盖过淡出动画即可消除残留。各透镜的拖拽落点统一走此修饰器,避免重复踩坑。
extension View {
    func deferredDrop(perform: @escaping (String) -> Void) -> some View {
        dropDestination(for: String.self) { dropped, _ in
            guard let payload = dropped.first else { return false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.18)) { perform(payload) }
            }
            return true
        }
    }
}
