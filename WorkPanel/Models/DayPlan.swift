import Foundation
import SwiftData

/// 某个自然日的「今日承诺」快照:那天主动挑出要推进的任务 ID。
/// 只存 ID,不建关系,删除任务时无级联;渲染时按 ID 取任务,取不到即跳过。
@Model
final class DayPlan {
    var day: Date                  // 归一化到当天 00:00(Calendar.startOfDay)
    var committedTaskIDs: [UUID]
    var modifiedAt: Date = Date()      // 跨机器同步的最新者胜判定

    init(day: Date, committedTaskIDs: [UUID] = []) {
        self.day = day
        self.committedTaskIDs = committedTaskIDs
    }
}

extension DayPlan: @preconcurrency Timestamped {}
