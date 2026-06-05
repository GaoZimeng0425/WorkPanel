import Foundation
import SwiftData

/// 带「最后修改时间」的模型。用于导入合并的最新者胜判定,以及 saveTracking 打点。
@preconcurrency protocol Timestamped: AnyObject {
    var modifiedAt: Date { get set }
}
