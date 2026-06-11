import Foundation
import SwiftData

/// 带「最后修改时间」的模型。用于导入合并的最新者胜判定,以及 saveTracking 打点。
@preconcurrency protocol Timestamped: AnyObject {
    var modifiedAt: Date { get set }
}

extension ModelContext {
    /// 保存前把所有「新插入 + 被修改」且符合 Timestamped 的模型的 modifiedAt 打成 now,然后保存。
    /// 导入合并路径刻意用普通 save() 以保留文件里的时间戳,故不要在那里用本方法。
    func saveTracking(now: Date = .now) throws {
        var seen = Set<ObjectIdentifier>()
        for model in insertedModelsArray + changedModelsArray {
            guard seen.insert(ObjectIdentifier(model)).inserted else { continue }
            guard !model.isDeleted else { continue }
            (model as? Timestamped)?.modifiedAt = now
        }
        try save()
    }
}
