//
//  Club.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct Club: Codable, Hashable {
    let id: String
    let name: String
    let member: [Player]
    let gameHistory: [GameByDay]
    let intendedGame: [GameByDay] // 최대 5개까지 저장 가능하도록 구현 예정
    let locations: [String]
}
