import Foundation
import SwiftData

enum TombstoneKind: String, Codable, Sendable { case task, column }

/// 删除墓碑:记录某条记录被删除的事实,用于跨设备传播删除、抑制对端复活。
/// 刻意不实现 Timestamped——它从不被编辑,merge 用普通 save() 不会重新打点 deletedAt。
@Model
final class Tombstone {
    @Attribute(.unique) var id: UUID   // 被删记录的 id;按 id 去重,store 层强制唯一
    var kindRaw: String
    var deletedAt: Date

    init(id: UUID, kind: TombstoneKind, deletedAt: Date) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.deletedAt = deletedAt
    }

    var kind: TombstoneKind { TombstoneKind(rawValue: kindRaw) ?? .task }
}
