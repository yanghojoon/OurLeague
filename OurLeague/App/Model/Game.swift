//
//  Game.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct GameByDay: Codable {
    let date: Date
    let startTime: Date
    let endTime: Date
    let games: [Game]
    let participants: [Player]
}

struct Game: Codable {
    let teamA: [Player]
    let teamB: [Player]
    let score: [Int]
}
