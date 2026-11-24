//
//  ClubRosterStore.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import Foundation
import Combine

struct SaveParticipantCommand: Encodable, Equatable {
    struct Payload: Encodable, Equatable {
        let clubID: UUID
        let participantID: UUID?
        let displayName: String
        let label: String?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case clubID = "club_id"
            case participantID = "participant_id"
            case displayName = "display_name"
            case label
            case isActive = "is_active"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clubID, forKey: .clubID)
            try container.encodeIfPresent(participantID, forKey: .participantID)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(isActive, forKey: .isActive)
        }
    }

    let operation = "save_participant"
    let payload: Payload
    let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case operation, payload
        case requestID = "request_id"
    }

    init(clubID: UUID, participantID: UUID?, displayName: String, label: String, isActive: Bool, requestID: UUID = UUID()) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(name.unicodeScalars.count), participantID != nil || isActive else {
            throw RosterError.invalidInput
        }
        payload = Payload(clubID: clubID, participantID: participantID, displayName: name,
                          label: normalizedLabel.isEmpty ? nil : normalizedLabel,
                          isActive: participantID == nil ? nil : isActive)
        self.requestID = requestID
    }
}

enum RosterError: Error {
    case invalidInput, invalidResponse, permissionDenied
}

@MainActor
protocol LeagueRosterService {
    func fetchParticipants(clubID: UUID, accountID: UUID) async throws -> [ClubParticipant]
    func saveParticipant(_ command: SaveParticipantCommand, accountID: UUID) async throws -> UUID
}

@MainActor
final class ClubRosterStore: ObservableObject {
    @Published private(set) var state: ClubListState = .loading
    @Published private(set) var participants: [ClubParticipant] = []
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    var canManage: Bool { membership.canManage }

    private let membership: ClubMembership
    private let makeService: () throws -> any LeagueRosterService
    private var service: (any LeagueRosterService)?
    private var pendingCommand: SaveParticipantCommand?

    init(membership: ClubMembership, makeService: @escaping () throws -> any LeagueRosterService) {
        self.membership = membership
        self.makeService = makeService
    }

    func load() async {
        guard !isBusy, !Task.isCancelled else { return }
        isBusy = true
        state = .loading
        participants = []
        errorMessage = nil
        defer { isBusy = false }
        do {
            guard membership.membership.status == .approved,
                  membership.membership.clubID == membership.club.id else { throw RosterError.permissionDenied }
            let fetched = try await resolvedService().fetchParticipants(clubID: membership.id, accountID: membership.membership.accountID)
            try Task.checkCancellation()
            try validate(fetched)
            participants = fetched
            state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .unavailable
            errorMessage = "명단을 불러오지 못했습니다. 소속과 연결 상태를 확인하고 다시 시도하세요."
        }
    }

    func save(participantID: UUID?, displayName: String, label: String, isActive: Bool) async -> Bool {
        guard !isBusy, !Task.isCancelled, state == .loaded, canManage else { return false }
        guard participantID == nil || participants.contains(where: { $0.id == participantID }) else { return false }
        let command: SaveParticipantCommand
        do {
            let candidate = try SaveParticipantCommand(clubID: membership.id, participantID: participantID,
                                                       displayName: displayName, label: label, isActive: isActive)
            if let pendingCommand, pendingCommand.payload == candidate.payload {
                command = pendingCommand
            } else {
                command = candidate
            }
        } catch {
            errorMessage = "이름은 앞뒤 공백을 제외하고 1~40자로 입력하세요."
            return false
        }
        pendingCommand = command
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let service = try resolvedService()
            let savedID = try await service.saveParticipant(command, accountID: membership.membership.accountID)
            try Task.checkCancellation()
            guard participantID == nil || savedID == participantID else { throw RosterError.invalidResponse }
            let fetched = try await service.fetchParticipants(clubID: membership.id, accountID: membership.membership.accountID)
            try Task.checkCancellation()
            try validate(fetched)
            guard let saved = fetched.first(where: { $0.id == savedID }),
                  saved.displayName == command.payload.displayName,
                  saved.label == command.payload.label,
                  saved.isActive == (command.payload.isActive ?? true) else { throw RosterError.invalidResponse }
            participants = fetched
            pendingCommand = nil
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = "저장 또는 저장 후 명단 확인에 실패했습니다. 표시된 명단은 최신이 아닐 수 있습니다. 같은 내용으로 재시도하거나 취소 후 새로고침하세요."
            return false
        }
    }

    private func validate(_ fetched: [ClubParticipant]) throws {
        guard fetched.allSatisfy({ $0.clubID == membership.id }),
              Set(fetched.map(\.id)).count == fetched.count else { throw RosterError.invalidResponse }
    }

    private func resolvedService() throws -> any LeagueRosterService {
        if let service { return service }
        let created = try makeService()
        service = created
        return created
    }
}
