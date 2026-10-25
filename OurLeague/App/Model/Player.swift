//
//  Player.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct ClubParticipant: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    let accountID: UUID?
    let displayName: String
    let label: String?
    let isActive: Bool
    let legacyPlayerID: Int64?

    enum CodingKeys: String, CodingKey {
        case id, label
        case clubID = "club_id"
        case accountID = "account_id"
        case displayName = "display_name"
        case isActive = "is_active"
        case legacyPlayerID = "legacy_player_id"
    }
}

struct SessionParticipant: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let clubParticipantID: UUID?
    let accountID: UUID?
    let displayName: String
    let response: AttendanceResponse
    let approval: ParticipantApproval

    enum CodingKeys: String, CodingKey {
        case id, response, approval
        case sessionID = "session_id"
        case clubParticipantID = "club_participant_id"
        case accountID = "account_id"
        case displayName = "display_name"
    }
}

enum AttendanceResponse: String, Codable, Sendable {
    case attending, declined
}

enum ParticipantApproval: String, Codable, Sendable {
    case pending, approved, rejected
}

struct ParticipantStats: Codable, Hashable, Sendable {
    let clubID: UUID
    let participantID: UUID
    let displayName: String
    let wins: Int
    let losses: Int
    let completedMatches: Int
    let appearances: Int
    let winRate: Double?

    enum CodingKeys: String, CodingKey {
        case wins, losses, appearances
        case clubID = "club_id"
        case participantID = "participant_id"
        case displayName = "display_name"
        case completedMatches = "completed_matches"
        case winRate = "win_rate"
    }
}
