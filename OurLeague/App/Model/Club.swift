//
//  Club.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import Foundation

struct Club: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let ownerAccountID: UUID?
    let status: ClubStatus
    let legacyID: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, description, status
        case ownerAccountID = "owner_account_id"
        case legacyID = "legacy_id"
    }
}

enum ClubStatus: String, Codable, Sendable {
    case active, closed
    case needsOwner = "needs_owner"
}

struct Membership: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    let accountID: UUID
    let role: MembershipRole
    let status: MembershipStatus

    enum CodingKeys: String, CodingKey {
        case id, role, status
        case clubID = "club_id"
        case accountID = "account_id"
    }
}

enum MembershipRole: String, Codable, Sendable {
    case owner, member
}

enum MembershipStatus: String, Codable, Sendable {
    case pending, approved, inactive
}

struct AccountProfile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}
