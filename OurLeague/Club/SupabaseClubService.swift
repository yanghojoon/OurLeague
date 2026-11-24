//
//  SupabaseClubService.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import Foundation
import Supabase

@MainActor
final class SupabaseClubService: LeagueClubService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchMemberships(accountID: UUID) async throws -> [ClubMembership] {
        try await validateSession(accountID: accountID)
        var memberships: [ClubMembership] = []
        let pageSize = 200
        while true {
            try Task.checkCancellation()
            let page: [ClubMembership] = try await client
                .from("memberships")
                .select("id,club_id,account_id,role,status,club:clubs(id,name,description,owner_account_id,status,legacy_id)")
                .eq("account_id", value: accountID.uuidString)
                .eq("status", value: "approved")
                .order("id")
                .range(from: memberships.count, to: memberships.count + pageSize - 1)
                .execute()
                .value
            memberships.append(contentsOf: page)
            if page.count < pageSize { break }
        }
        try await validateSession(accountID: accountID)
        return memberships
    }

    func createClub(_ command: CreateClubCommand, accountID: UUID) async throws -> Club {
        try await validateSession(accountID: accountID)
        let club: Club = try await client
            .rpc("league_command", params: command)
            .execute()
            .value
        guard club.ownerAccountID == accountID else { throw ClubError.unexpectedOwner }
        return club
    }

    private func validateSession(accountID: UUID) async throws {
        let session = try await client.auth.session
        try Task.checkCancellation()
        guard session.user.id == accountID else { throw ClubError.invalidMembership }
    }
}
