import SwiftUI
import SwiftData

/// 甘特透镜:任务按时间范围画成横条,可拖动/拉伸改起止。
struct GanttLensView: View {
    var body: some View {
        Text("甘特图")
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
