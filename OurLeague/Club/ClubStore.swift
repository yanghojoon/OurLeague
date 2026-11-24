//
//  ClubStore.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import Foundation
import Combine

struct ClubMembership: Decodable, Hashable, Identifiable {
    let membership: Membership
    let club: Club
    var id: UUID { club.id }
    var canManage: Bool {
        membership.status == .approved && membership.role == .owner &&
        club.status == .active && club.ownerAccountID == membership.accountID
    }

    init(membership: Membership, club: Club) {
        self.membership = membership
        self.club = club
    }

    init(from decoder: Decoder) throws {
        membership = try Membership(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        club = try container.decode(Club.self, forKey: .club)
    }

    private enum CodingKeys: String, CodingKey {
        case club
    }
}

struct CreateClubCommand: Encodable, Equatable {
    struct Payload: Encodable, Equatable {
        let name: String
        let description: String
    }

    let operation = "create_club"
    let payload: Payload
    let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case operation, payload
        case requestID = "request_id"
    }

    init(name: String, description: String, requestID: UUID = UUID()) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(normalized.unicodeScalars.count) else {
            throw ClubError.invalidName
        }
        payload = Payload(name: normalized, description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        self.requestID = requestID
    }
}

enum ClubError: Error {
    case invalidName, invalidMembership, unexpectedOwner
}

enum ClubListState: Equatable {
    case loading, loaded, unavailable
}

@MainActor
protocol LeagueClubService {
    func fetchMemberships(accountID: UUID) async throws -> [ClubMembership]
    func createClub(_ command: CreateClubCommand, accountID: UUID) async throws -> Club
}

@MainActor
final class ClubStore: ObservableObject {
    @Published private(set) var state: ClubListState = .loading
    @Published private(set) var memberships: [ClubMembership] = []
    @Published private(set) var selectedClubID: UUID?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    var selectedMembership: ClubMembership? {
        memberships.first { $0.id == selectedClubID }
    }

    private let accountID: UUID
    private let makeService: () throws -> any LeagueClubService
    private var service: (any LeagueClubService)?
    private var pendingCommand: CreateClubCommand?

    init(accountID: UUID, makeService: @escaping () throws -> any LeagueClubService) {
        self.accountID = accountID
        self.makeService = makeService
    }

    func load() async {
        guard !isBusy, !Task.isCancelled else { return }
        isBusy = true
        state = .loading
        memberships = []
        selectedClubID = nil
        errorMessage = nil
        defer { isBusy = false }
        do {
            let fetched = try await resolvedService().fetchMemberships(accountID: accountID)
            try Task.checkCancellation()
            try validate(fetched)
            memberships = fetched
            state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .unavailable
            errorMessage = "동호회 목록을 불러오지 못했습니다. 다시 시도하세요."
        }
    }

    func select(clubID: UUID?) {
        guard !isBusy, state == .loaded else { return }
        guard clubID == nil || memberships.contains(where: { $0.id == clubID }) else { return }
        selectedClubID = clubID
    }

    func create(name: String, description: String) async -> Bool {
        guard !isBusy, !Task.isCancelled, state == .loaded else { return false }
        let command: CreateClubCommand
        do {
            let candidate = try CreateClubCommand(name: name, description: description)
            if let pendingCommand, pendingCommand.payload == candidate.payload {
                command = pendingCommand
            } else {
                command = candidate
            }
        } catch {
            errorMessage = "동호회 이름은 앞뒤 공백을 제외하고 1~100자로 입력하세요."
            return false
        }
        pendingCommand = command
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let service = try resolvedService()
            let club = try await service.createClub(command, accountID: accountID)
            try Task.checkCancellation()
            guard club.ownerAccountID == accountID, club.status == .active else {
                throw ClubError.unexpectedOwner
            }
            let fetched = try await service.fetchMemberships(accountID: accountID)
            try Task.checkCancellation()
            try validate(fetched)
            guard fetched.contains(where: { $0.id == club.id && $0.canManage }) else {
                throw ClubError.invalidMembership
            }
            memberships = fetched
            selectedClubID = club.id
            pendingCommand = nil
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = "동호회 생성 또는 소속 확인에 실패했습니다. 같은 내용으로 다시 시도하면 중복 생성되지 않습니다."
            return false
        }
    }

    private func validate(_ fetched: [ClubMembership]) throws {
        guard Set(fetched.map(\.id)).count == fetched.count,
              fetched.allSatisfy({
                  $0.membership.accountID == accountID && $0.membership.status == .approved &&
                  $0.membership.clubID == $0.club.id &&
                  ($0.membership.role != .owner || $0.club.ownerAccountID == accountID)
              }) else { throw ClubError.invalidMembership }
    }

    private func resolvedService() throws -> any LeagueClubService {
        if let service { return service }
        let created = try makeService()
        service = created
        return created
    }
}
