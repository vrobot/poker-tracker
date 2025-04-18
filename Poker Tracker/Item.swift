//
//  Item.swift
//  Poker Tracker
//
//  Created by Venkat Krishnan on 4/18/25.
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
