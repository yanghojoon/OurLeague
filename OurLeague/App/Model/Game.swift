//
//  Game.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct GameByDay: Codable, Hashable {
    let date: Date
    let startTime: Date
    let endTime: Date
    let games: [Game]
    let participants: [Player]
    let location: String
}

struct Game: Codable, Hashable {
    let teamA: [Player]
    let teamB: [Player]
    let score: [Int]
}
