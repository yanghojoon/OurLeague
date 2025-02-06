//
//  Player.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct Player: Decodable {
    let name: String
    let club: Club
    let totalGameCount: Int
    let winCount: Int
}

struct Club: Decodable {
    let id: String
    let name: String
    let member: [Player]
}
