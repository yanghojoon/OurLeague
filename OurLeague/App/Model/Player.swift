//
//  Player.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct Player: Codable, Hashable {
    let name: String
    let club: Club
    let totalGameCount: Int
    let winCount: Int
    let ranking: Int
}
