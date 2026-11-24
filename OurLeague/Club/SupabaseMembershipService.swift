//
//  SupabaseMembershipService.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import Foundation
import Supabase

@MainActor
final class SupabaseMembershipService: LeagueMembershipService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchOwnMemberships(accountID: UUID) async throws -> [Membership] {
        try await fetchMemberships(accountID: accountID, clubID: nil)
    }

    func fetchClubMemberships(clubID: UUID, accountID: UUID) async throws -> [Membership] {
        try await fetchMemberships(accountID: accountID, clubID: clubID)
    }

    func fetchParticipants(clubID: UUID, accountID: UUID) async throws -> [ClubParticipant] {
        try await SupabaseRosterService(client: client).fetchParticipants(clubID: clubID, accountID: accountID)
    }

    func issueInvitation(clubID: UUID, accountID: UUID, expiresAt: Date) async throws -> MembershipInvitation {
        try await validateSession(accountID: accountID)
        let params = IssueMembershipInvitation(clubID: clubID, expiresAt: ISO8601DateFormatter().string(from: expiresAt))
        let invitation: MembershipInvitation = try await client.rpc("issue_invitation", params: params).execute().value
        try await validateSession(accountID: accountID)
        return invitation
    }

    func execute(_ command: MembershipCommand, accountID: UUID) async throws -> MembershipReceipt {
        try await validateSession(accountID: accountID)
        let receipt: MembershipReceipt = try await client.rpc("league_command", params: command).execute().value
        try await validateSession(accountID: accountID)
        return receipt
    }

    private func fetchMemberships(accountID: UUID, clubID: UUID?) async throws -> [Membership] {
        try await validateSession(accountID: accountID)
        var memberships: [Membership] = []
        let pageSize = 200
        while true {
            try Task.checkCancellation()
            let query = client.from("memberships").select("id,club_id,account_id,role,status")
            if let clubID {
                _ = query.eq("club_id", value: clubID.uuidString)
            } else {
                _ = query.eq("account_id", value: accountID.uuidString)
            }
            let page: [Membership] = try await query.order("id")
                .range(from: memberships.count, to: memberships.count + pageSize - 1)
                .execute().value
            memberships.append(contentsOf: page)
            if page.count < pageSize { break }
        }
        try await validateSession(accountID: accountID)
        return memberships
    }

    private func validateSession(accountID: UUID) async throws {
        let session = try await client.auth.session
        try Task.checkCancellation()
        guard session.user.id == accountID else { throw MembershipError.permissionDenied }
    }
}

struct IssueMembershipInvitation: Encodable {
    let clubID: UUID
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case clubID = "target_club"
        case sessionID = "target_session"
        case expiresAt = "expires_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clubID, forKey: .clubID)
        try container.encodeNil(forKey: .sessionID)
        try container.encode(expiresAt, forKey: .expiresAt)
    }
}
