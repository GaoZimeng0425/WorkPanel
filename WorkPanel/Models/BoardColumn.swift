import Foundation
import SwiftData

@Model
final class BoardColumn {
    var id: UUID
    var name: String
    var order: Int
    var sortRaw: String? = nil         // 列内排序选项的 rawValue,nil 即手动
    var modifiedAt: Date = Date()      // 跨机器同步的最新者胜判定

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
    }

    /// 当前列内排序选项;nil 或未知 rawValue 均回退手动。
    @MainActor var sort: ColumnSortOption { ColumnSortOption.from(raw: sortRaw) }
}

extension BoardColumn: @preconcurrency Timestamped {}
