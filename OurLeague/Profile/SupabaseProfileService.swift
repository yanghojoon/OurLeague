//
//  SupabaseProfileService.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/17.
//

import Foundation
import Supabase

@MainActor
final class SupabaseProfileService: LeagueProfileService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchProfile(accountID: UUID) async throws -> AccountProfile? {
        let profiles: [AccountProfile] = try await client
            .from("profiles")
            .select("id,display_name")
            .eq("id", value: accountID.uuidString)
            .execute()
            .value
        guard profiles.count <= 1,
              profiles.allSatisfy({ $0.id == accountID }) else {
            throw ProfileError.unexpectedAccount
        }
        return profiles.first
    }

    func saveProfile(_ command: SaveProfileCommand, accountID: UUID) async throws -> AccountProfile {
        let session = try await client.auth.session
        try Task.checkCancellation()
        guard session.user.id == accountID else { throw ProfileError.unexpectedAccount }
        let response: SavedProfile = try await client
            .rpc("league_command", params: command)
            .execute()
            .value
        guard response.id == accountID else { throw ProfileError.unexpectedAccount }
        return AccountProfile(id: response.id, displayName: command.payload.displayName)
    }

    private struct SavedProfile: Decodable {
        let id: UUID
    }
}
