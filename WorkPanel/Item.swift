//
//  Item.swift
//  WorkPanel
//
//  Created by GaoZimeng on 2026/5/29.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
