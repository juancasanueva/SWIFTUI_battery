//
//  Item.swift
//  battery
//
//  Created by Juan Casanueva on 22/10/2026.
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
