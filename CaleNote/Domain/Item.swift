//
//  Item.swift
//  CaleNote
//
//  Created by Masaya Kawai on 2025/12/20.
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
