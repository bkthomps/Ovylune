//
//  Item.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
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
