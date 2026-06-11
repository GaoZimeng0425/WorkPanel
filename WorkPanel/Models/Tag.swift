import Foundation
import SwiftData

/// 标签注册表实体:标签全集 + 顺序的权威来源。
/// 任务仍按名字(tags: [String])引用标签;身份用 name 而非 UUID,
/// 使两台设备各自建的同名标签天然合并。
@Model
final class Tag {
    @Attribute(.unique) var name: String
    var order: Int
    var modifiedAt: Date = Date()   // Timestamped 约定;v1 不同步,留作日后同步地基

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }
}

extension Tag: @preconcurrency Timestamped {}
