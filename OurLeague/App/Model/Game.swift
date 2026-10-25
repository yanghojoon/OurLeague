//
//  Game.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct LeagueSession: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    let title: String
    let startsAt: Date?
    let endsAt: Date?
    let location: String?
    let capacity: Int
    let courtCount: Int
    let roundCount: Int
    let attendanceDeadline: Date?
    let notice: String
    let status: SessionStatus
    let rosterVersion: Int
    let scheduleVersion: Int
    let scheduleStale: Bool
    let seed: Int64?
    let legacyID: Int64?
    let legacyStartDate: String?
    let legacyEndDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, location, capacity, notice, status, seed
        case clubID = "club_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case courtCount = "court_count"
        case roundCount = "round_count"
        case attendanceDeadline = "attendance_deadline"
        case rosterVersion = "roster_version"
        case scheduleVersion = "schedule_version"
        case scheduleStale = "schedule_stale"
        case legacyID = "legacy_id"
        case legacyStartDate = "legacy_start_date"
        case legacyEndDate = "legacy_end_date"
    }
}

enum SessionStatus: String, Codable, Sendable {
    case needsReview = "needs_review"
    case recruiting, confirmed
    case inProgress = "in_progress"
    case completed, cancelled
}

struct SessionCourt: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let name: String
    let position: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case sessionID = "session_id"
        case isActive = "is_active"
    }
}

struct Match: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let roundIndex: Int?
    let courtID: UUID?
    let scheduleVersion: Int
    let status: MatchStatus
    let startedAt: Date?
    let finishedAt: Date?
    let legacyID: Int64?

    enum CodingKeys: String, CodingKey {
        case id, status
        case sessionID = "session_id"
        case roundIndex = "round_index"
        case courtID = "court_id"
        case scheduleVersion = "schedule_version"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case legacyID = "legacy_id"
    }
}

enum MatchStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed, aborted, cancelled
}

enum MatchTeam: String, Codable, Sendable {
    case a, b
}

struct MatchPlayer: Codable, Hashable, Sendable {
    let matchID: UUID
    let sessionID: UUID
    let participantID: UUID
    let team: MatchTeam
    let slot: Int

    enum CodingKeys: String, CodingKey {
        case team, slot
        case matchID = "match_id"
        case sessionID = "session_id"
        case participantID = "participant_id"
    }
}

struct MatchResult: Codable, Hashable, Sendable {
    let matchID: UUID
    let winner: MatchTeam
    let scoreA: Int?
    let scoreB: Int?
    let version: Int
    let isValid: Bool

    enum CodingKeys: String, CodingKey {
        case winner, version
        case matchID = "match_id"
        case scoreA = "score_a"
        case scoreB = "score_b"
        case isValid = "is_valid"
    }
}
