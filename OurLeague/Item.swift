//
//  Item.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
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
