//
//  SupabaseRosterService.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import Foundation
import Supabase

@MainActor
final class SupabaseRosterService: LeagueRosterService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchParticipants(clubID: UUID, accountID: UUID) async throws -> [ClubParticipant] {
        try await validateSession(accountID: accountID)
        var participants: [ClubParticipant] = []
        let pageSize = 200
        while true {
            try Task.checkCancellation()
            let page: [ClubParticipant] = try await client
                .from("club_participants")
                .select("id,club_id,account_id,display_name,label,is_active,legacy_player_id")
                .eq("club_id", value: clubID.uuidString)
                .order("id")
                .range(from: participants.count, to: participants.count + pageSize - 1)
                .execute()
                .value
            participants.append(contentsOf: page)
            if page.count < pageSize { break }
        }
        try await validateSession(accountID: accountID)
        return participants
    }

    func saveParticipant(_ command: SaveParticipantCommand, accountID: UUID) async throws -> UUID {
        try await validateSession(accountID: accountID)
        let receipt: ParticipantReceipt = try await client
            .rpc("league_command", params: command)
            .execute()
            .value
        try await validateSession(accountID: accountID)
        return receipt.participantID
    }

    private func validateSession(accountID: UUID) async throws {
        let session = try await client.auth.session
        try Task.checkCancellation()
        guard session.user.id == accountID else { throw RosterError.permissionDenied }
    }

    private struct ParticipantReceipt: Decodable {
        let participantID: UUID

        enum CodingKeys: String, CodingKey {
            case participantID = "participant_id"
        }
    }
}
