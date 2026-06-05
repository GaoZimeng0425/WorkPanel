import Foundation
import SwiftData

@Model
final class BoardColumn {
    var id: UUID
    var name: String
    var order: Int
    var modifiedAt: Date = Date()

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
    }
}

extension BoardColumn: @preconcurrency Timestamped {}
