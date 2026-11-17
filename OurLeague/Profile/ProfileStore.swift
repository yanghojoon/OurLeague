//
//  ProfileStore.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/17.
//

import Foundation
import Combine

struct SaveProfileCommand: Encodable, Equatable {
    struct Payload: Encodable, Equatable {
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    let operation = "save_profile"
    let payload: Payload
    let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case operation, payload
        case requestID = "request_id"
    }

    init(displayName: String, requestID: UUID = UUID()) throws {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(normalized.unicodeScalars.count) else {
            throw ProfileError.invalidName
        }
        payload = Payload(displayName: normalized)
        self.requestID = requestID
    }
}

enum ProfileError: Error {
    case invalidName, unexpectedAccount
}

enum ProfileState: Equatable {
    case loading, needsName, unavailable
    case ready(AccountProfile)
}

@MainActor
protocol LeagueProfileService {
    func fetchProfile(accountID: UUID) async throws -> AccountProfile?
    func saveProfile(_ command: SaveProfileCommand, accountID: UUID) async throws -> AccountProfile
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var state: ProfileState = .loading
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    private let accountID: UUID
    private let makeService: () throws -> any LeagueProfileService
    private var service: (any LeagueProfileService)?
    private var pendingCommand: SaveProfileCommand?

    init(accountID: UUID, makeService: @escaping () throws -> any LeagueProfileService) {
        self.accountID = accountID
        self.makeService = makeService
    }

    func load() async {
        guard !isBusy, !Task.isCancelled else { return }
        if case .ready = state { return }
        isBusy = true
        state = .loading
        errorMessage = nil
        defer { isBusy = false }

        do {
            let profile = try await resolvedService().fetchProfile(accountID: accountID)
            try Task.checkCancellation()
            if let profile {
                try validate(profile)
                state = .ready(profile)
            } else {
                state = .needsName
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .unavailable
            errorMessage = "프로필을 불러오지 못했습니다. 연결 상태를 확인하고 다시 시도하세요."
        }
    }

    func save(displayName: String) async {
        guard !isBusy, !Task.isCancelled, state == .needsName else { return }
        let command: SaveProfileCommand
        do {
            let candidate = try SaveProfileCommand(displayName: displayName)
            if let pendingCommand, pendingCommand.payload == candidate.payload {
                command = pendingCommand
            } else {
                command = candidate
            }
        } catch {
            errorMessage = "닉네임은 앞뒤 공백을 제외하고 1~40자로 입력하세요."
            return
        }

        pendingCommand = command
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let profile = try await resolvedService().saveProfile(command, accountID: accountID)
            try Task.checkCancellation()
            try validate(profile)
            pendingCommand = nil
            state = .ready(profile)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "닉네임을 저장하지 못했습니다. 다시 시도하세요."
        }
    }

    private func resolvedService() throws -> any LeagueProfileService {
        if let service { return service }
        let created = try makeService()
        service = created
        return created
    }

    private func validate(_ profile: AccountProfile) throws {
        guard profile.id == accountID else { throw ProfileError.unexpectedAccount }
        _ = try SaveProfileCommand(displayName: profile.displayName)
    }
}
