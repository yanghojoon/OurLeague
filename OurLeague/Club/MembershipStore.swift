//
//  MembershipStore.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import Foundation
import Combine

struct MembershipCommand: Encodable, Equatable, CustomDebugStringConvertible {
    enum Operation: String, Encodable {
        case request = "request_membership"
        case approve = "approve_membership"
        case link = "save_participant"
        case revoke = "revoke_invitation"
    }

    struct Payload: Encodable, Equatable {
        var token: String?
        var clubID: UUID?
        var membershipID: UUID?
        var participantID: UUID?
        var accountID: UUID?
        var invitationID: UUID?

        enum CodingKeys: String, CodingKey {
            case token
            case clubID = "club_id"
            case membershipID = "membership_id"
            case participantID = "participant_id"
            case accountID = "account_id"
            case invitationID = "invitation_id"
        }
    }

    let operation: Operation
    let payload: Payload
    let requestID: UUID
    var debugDescription: String { "MembershipCommand(\(operation.rawValue), redacted)" }

    enum CodingKeys: String, CodingKey {
        case operation, payload
        case requestID = "request_id"
    }

    init(operation: Operation, payload: Payload, requestID: UUID = UUID()) {
        self.operation = operation
        self.payload = payload
        self.requestID = requestID
    }

    static func request(token: String) throws -> MembershipCommand {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidToken(normalized) else { throw MembershipError.invalidToken }
        return MembershipCommand(operation: .request, payload: Payload(token: normalized))
    }

    static func isValidToken(_ token: String) -> Bool {
        token.utf8.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct MembershipReceipt: Decodable {
    let membershipID: UUID?
    let participantID: UUID?
    let revoked: Bool?

    enum CodingKeys: String, CodingKey {
        case membershipID = "membership_id"
        case participantID = "participant_id"
        case revoked
    }
}

struct MembershipInvitation: Decodable, CustomDebugStringConvertible {
    let id: UUID
    let token: String
    let expiresAt: String
    var debugDescription: String { "MembershipInvitation(redacted)" }

    enum CodingKeys: String, CodingKey {
        case id = "invitation_id"
        case token
        case expiresAt = "expires_at"
    }

    var expirationDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    func isUsable(at date: Date) -> Bool {
        MembershipCommand.isValidToken(token) && (expirationDate.map { $0 > date } ?? false)
    }
}

enum MembershipError: Error {
    case invalidToken, invalidResponse, permissionDenied
}

@MainActor
protocol LeagueMembershipService {
    func fetchOwnMemberships(accountID: UUID) async throws -> [Membership]
    func fetchClubMemberships(clubID: UUID, accountID: UUID) async throws -> [Membership]
    func fetchParticipants(clubID: UUID, accountID: UUID) async throws -> [ClubParticipant]
    func issueInvitation(clubID: UUID, accountID: UUID, expiresAt: Date) async throws -> MembershipInvitation
    func execute(_ command: MembershipCommand, accountID: UUID) async throws -> MembershipReceipt
}

@MainActor
final class MembershipRequestStore: ObservableObject {
    @Published private(set) var state: ClubListState = .loading
    @Published private(set) var memberships: [Membership] = []
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    private let accountID: UUID
    private let makeService: () throws -> any LeagueMembershipService
    private var service: (any LeagueMembershipService)?
    private var pendingCommand: MembershipCommand?

    init(accountID: UUID, makeService: @escaping () throws -> any LeagueMembershipService) {
        self.accountID = accountID
        self.makeService = makeService
    }

    func load() async {
        guard !isBusy, !Task.isCancelled else { return }
        isBusy = true
        memberships = []
        state = .loading
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }
        do {
            memberships = try await fetchValidated()
            state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .unavailable
            errorMessage = "가입 상태를 확인하지 못했습니다. 다시 시도하세요."
        }
    }

    func request(token: String) async -> Bool {
        guard !isBusy, !Task.isCancelled, state == .loaded else { return false }
        successMessage = nil
        let command: MembershipCommand
        do {
            let candidate = try MembershipCommand.request(token: token)
            if let pendingCommand, pendingCommand.payload == candidate.payload {
                command = pendingCommand
            } else {
                command = candidate
            }
        } catch {
            errorMessage = "운영자가 공유한 64자리 초대 코드를 입력하세요."
            return false
        }
        pendingCommand = command
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let receipt = try await resolvedService().execute(command, accountID: accountID)
            try Task.checkCancellation()
            let fetched = try await fetchValidated()
            guard let joined = fetched.first(where: { $0.id == receipt.membershipID }),
                  joined.status == .pending || joined.status == .approved else { throw MembershipError.invalidResponse }
            memberships = fetched
            successMessage = joined.status == .approved ? "이미 승인된 동호회입니다. 내 동호회 목록을 새로고침하세요." : "가입 신청을 확인했습니다. 운영자 승인을 기다려 주세요."
            pendingCommand = nil
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = "가입 신청 또는 상태 확인에 실패했습니다. 만료·폐기된 코드는 사용할 수 없습니다. 같은 코드로 재시도하거나 새로고침하세요."
            return false
        }
    }

    private func fetchValidated() async throws -> [Membership] {
        let fetched = try await resolvedService().fetchOwnMemberships(accountID: accountID)
        try Task.checkCancellation()
        guard fetched.allSatisfy({ $0.accountID == accountID }),
              Set(fetched.map(\.id)).count == fetched.count,
              Set(fetched.map(\.clubID)).count == fetched.count else { throw MembershipError.invalidResponse }
        return fetched
    }

    private func resolvedService() throws -> any LeagueMembershipService {
        if let service { return service }
        let created = try makeService()
        service = created
        return created
    }
}

@MainActor
final class MembershipManagementStore: ObservableObject {
    @Published private(set) var state: ClubListState = .loading
    @Published private(set) var memberships: [Membership] = []
    @Published private(set) var participants: [ClubParticipant] = []
    @Published private(set) var invitation: MembershipInvitation?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var revokingInvitationID: UUID?

    var canManage: Bool { membership.canManage && membership.membership.clubID == membership.id }

    private let membership: ClubMembership
    private let makeService: () throws -> any LeagueMembershipService
    private var service: (any LeagueMembershipService)?
    private var pendingCommand: MembershipCommand?
    private var accountID: UUID { membership.membership.accountID }

    init(membership: ClubMembership, makeService: @escaping () throws -> any LeagueMembershipService) {
        self.membership = membership
        self.makeService = makeService
    }

    func load() async {
        guard !isBusy, !Task.isCancelled else { return }
        isBusy = true
        state = .loading
        memberships = []
        participants = []
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }
        do {
            guard canManage else { throw MembershipError.permissionDenied }
            let snapshot = try await fetchValidated()
            memberships = snapshot.members
            participants = snapshot.roster
            state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .unavailable
            invitation = nil
            errorMessage = "회원 정보를 확인하지 못했습니다. 운영자 권한과 연결 상태를 확인하세요."
        }
    }

    func issueInvitation(now: Date = Date()) async {
        guard canManage, state == .loaded, !isBusy, !Task.isCancelled else { return }
        isBusy = true
        invitation = nil
        errorMessage = nil
        successMessage = nil
        defer { isBusy = false }
        do {
            let issued = try await resolvedService().issueInvitation(clubID: membership.id, accountID: accountID,
                                                                    expiresAt: now.addingTimeInterval(86400))
            try Task.checkCancellation()
            guard issued.isUsable(at: Date()) else { throw MembershipError.invalidResponse }
            invitation = issued
            revokingInvitationID = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "초대 발급을 확인하지 못했습니다. 이전 코드가 폐기되었을 수 있습니다. 다시 발급하면 이전 회원 초대 코드는 사용할 수 없습니다."
        }
    }

    func approve(membershipID: UUID) async -> Bool {
        guard canManage, state == .loaded,
              let member = memberships.first(where: { $0.id == membershipID }), member.role == .member,
              member.status == .pending || member.status == .approved else { return false }
        return await submit(MembershipCommand(operation: .approve,
                                             payload: .init(clubID: membership.id, membershipID: membershipID)))
    }

    func link(accountID: UUID, participantID: UUID) async -> Bool {
        guard canManage, state == .loaded,
              memberships.contains(where: { $0.accountID == accountID && $0.status == .approved }),
              let participant = participants.first(where: { $0.id == participantID }), participant.isActive,
              participant.accountID == nil || participant.accountID == accountID,
              !participants.contains(where: { $0.isActive && $0.accountID == accountID && $0.id != participantID }) else { return false }
        return await submit(MembershipCommand(operation: .link,
                                             payload: .init(clubID: membership.id, participantID: participantID, accountID: accountID)))
    }

    func revokeInvitation() async -> Bool {
        guard canManage, let invitationID = invitation?.id ?? revokingInvitationID else { return false }
        return await submit(MembershipCommand(operation: .revoke,
                                             payload: .init(clubID: membership.id, invitationID: invitationID)))
    }

    private func submit(_ candidate: MembershipCommand) async -> Bool {
        guard !isBusy, !Task.isCancelled else { return false }
        let command: MembershipCommand
        if let pendingCommand, pendingCommand.operation == candidate.operation, pendingCommand.payload == candidate.payload {
            command = pendingCommand
        } else {
            command = candidate
        }
        pendingCommand = command
        isBusy = true
        errorMessage = nil
        successMessage = nil
        if command.operation == .revoke {
            revokingInvitationID = command.payload.invitationID
            invitation = nil
        }
        defer { isBusy = false }
        do {
            if command.operation == .link {
                let latest = try await fetchValidated()
                guard latest.members.contains(where: { $0.accountID == command.payload.accountID && $0.status == .approved }),
                      let target = latest.roster.first(where: { $0.id == command.payload.participantID }), target.isActive,
                      target.accountID == nil || target.accountID == command.payload.accountID,
                      !latest.roster.contains(where: {
                          $0.isActive && $0.accountID == command.payload.accountID && $0.id != command.payload.participantID
                      }) else { throw MembershipError.invalidResponse }
            }
            let receipt = try await resolvedService().execute(command, accountID: accountID)
            try Task.checkCancellation()
            if command.operation == .revoke {
                guard receipt.revoked == true else { throw MembershipError.invalidResponse }
                revokingInvitationID = nil
                successMessage = "이 초대 코드를 폐기했습니다. 기존 가입 신청과 승인은 유지됩니다."
            } else {
                if command.operation == .approve {
                    guard receipt.membershipID == command.payload.membershipID else { throw MembershipError.invalidResponse }
                } else {
                    guard receipt.participantID == command.payload.participantID else { throw MembershipError.invalidResponse }
                }
                let snapshot = try await fetchValidated()
                if command.operation == .approve {
                    guard snapshot.members.contains(where: { $0.id == command.payload.membershipID && $0.status == .approved }) else {
                        throw MembershipError.invalidResponse
                    }
                    successMessage = "가입 승인을 확인했습니다. 명단 연결은 별도로 선택하세요."
                } else {
                    guard snapshot.roster.contains(where: {
                        $0.id == command.payload.participantID && $0.accountID == command.payload.accountID && $0.isActive
                    }) else { throw MembershipError.invalidResponse }
                    successMessage = "회원 계정과 기존 참가자 연결을 확인했습니다."
                }
                memberships = snapshot.members
                participants = snapshot.roster
            }
            pendingCommand = nil
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = "처리 또는 처리 후 확인에 실패했습니다. 표시된 정보는 최신이 아닐 수 있습니다. 같은 작업을 재시도하거나 새로고침하세요."
            return false
        }
    }

    private func fetchValidated() async throws -> (members: [Membership], roster: [ClubParticipant]) {
        let service = try resolvedService()
        let members = try await service.fetchClubMemberships(clubID: membership.id, accountID: accountID)
        let roster = try await service.fetchParticipants(clubID: membership.id, accountID: accountID)
        try Task.checkCancellation()
        guard members.allSatisfy({ $0.clubID == membership.id }),
              Set(members.map(\.id)).count == members.count,
              Set(members.map(\.accountID)).count == members.count,
              members.contains(where: { $0.accountID == accountID && $0.role == .owner && $0.status == .approved }),
              roster.allSatisfy({ $0.clubID == membership.id }),
              Set(roster.map(\.id)).count == roster.count else { throw MembershipError.invalidResponse }
        return (members, roster)
    }

    private func resolvedService() throws -> any LeagueMembershipService {
        if let service { return service }
        let created = try makeService()
        service = created
        return created
    }
}
