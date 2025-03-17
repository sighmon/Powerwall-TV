//
//  Item.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
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
