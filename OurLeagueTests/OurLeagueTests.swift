//
//  OurLeagueTests.swift
//  OurLeagueTests
//
//  Created by 양호준 on 2023/12/12.
//

import XCTest
@testable import OurLeague

final class OurLeagueTests: XCTestCase {

    func testRosterCommandEncodesNullLabelWithoutAccountLink() throws {
        let command = try SaveParticipantCommand(clubID: UUID(), participantID: UUID(), displayName: " 선수 ", label: " \n", isActive: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(json["operation"] as? String, "save_participant")
        XCTAssertEqual(json["request_id"] as? String, command.requestID.uuidString)
        XCTAssertEqual(payload["display_name"] as? String, "선수")
        XCTAssertTrue(payload["label"] is NSNull)
        XCTAssertEqual(payload["is_active"] as? Bool, false)
        XCTAssertNotNil(payload["club_id"])
        XCTAssertNotNil(payload["participant_id"])
        XCTAssertNil(payload["account_id"])
    }

    func testRosterNameMatchesDatabaseScalarLimits() throws {
        let clubID = UUID()
        XCTAssertNoThrow(try SaveParticipantCommand(clubID: clubID, participantID: nil, displayName: "가", label: "", isActive: true))
        XCTAssertNoThrow(try SaveParticipantCommand(clubID: clubID, participantID: nil, displayName: String(repeating: "가", count: 40), label: "", isActive: true))
        for name in [" \n", String(repeating: "가", count: 41), String(repeating: "e\u{301}", count: 21)] {
            XCTAssertThrowsError(try SaveParticipantCommand(clubID: clubID, participantID: nil, displayName: name, label: "", isActive: true))
        }
        XCTAssertThrowsError(try SaveParticipantCommand(clubID: clubID, participantID: nil, displayName: "선수", label: "", isActive: false))
    }

    func testRosterCreationOmitsUpdateOnlyFields() throws {
        let command = try SaveParticipantCommand(clubID: UUID(), participantID: nil, displayName: "선수", label: " 오전반 ", isActive: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["label"] as? String, "오전반")
        XCTAssertNil(payload["participant_id"])
        XCTAssertNil(payload["is_active"])
        XCTAssertNil(payload["account_id"])
    }

    @MainActor
    func testRosterLoadsEmptyAndInactiveRows() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertTrue(store.participants.isEmpty)
        service.rows = [service.row(name: "동명이인"), service.row(name: "동명이인", active: false)]
        await store.load()
        XCTAssertEqual(store.participants.count, 2)
        XCTAssertEqual(store.participants[1].isActive, false)
    }

    @MainActor
    func testRosterRefreshFailureClearsStaleRowsAndCanRetry() async {
        let service = TestRosterService()
        service.rows = [service.row()]
        let store = service.store()
        await store.load()
        service.fetchFails = true
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertTrue(store.participants.isEmpty)
        service.fetchFails = false
        await store.load()
        XCTAssertEqual(store.participants, service.rows)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testRosterRejectsForeignAndDuplicateRows() async {
        let service = TestRosterService()
        let store = service.store()
        service.rows = [service.row(clubID: UUID())]
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        let row = service.row()
        service.rows = [row, row]
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertTrue(store.participants.isEmpty)
    }

    @MainActor
    func testRosterMemberCanReadButCannotSave() async {
        let service = TestRosterService()
        service.rows = [service.row()]
        let store = service.store(role: .member)
        await store.load()
        XCTAssertEqual(store.participants.count, 1)
        XCTAssertFalse(store.canManage)
        let success = await store.save(participantID: nil, displayName: "선수", label: "", isActive: true)
        XCTAssertFalse(success)
        XCTAssertTrue(service.commands.isEmpty)
    }

    @MainActor
    func testRosterPendingMembershipCannotRead() async {
        let service = TestRosterService()
        let store = service.store(role: .member, status: .pending)
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertEqual(service.fetchCount, 0)
    }

    @MainActor
    func testRosterClosedOwnerCannotSave() async {
        let service = TestRosterService()
        let store = service.store(clubStatus: .closed)
        await store.load()
        XCTAssertFalse(store.canManage)
        let success = await store.save(participantID: nil, displayName: "선수", label: "", isActive: true)
        XCTAssertFalse(success)
        XCTAssertTrue(service.commands.isEmpty)
    }

    @MainActor
    func testRosterCreationRequiresRefetchBeforeSuccess() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        service.onSave = {
            XCTAssertTrue(store.participants.isEmpty)
            XCTAssertTrue(store.isBusy)
        }
        let success = await store.save(participantID: nil, displayName: " 선수 ", label: " A ", isActive: true)
        XCTAssertTrue(success)
        XCTAssertEqual(store.participants.first?.displayName, "선수")
        XCTAssertEqual(store.participants.first?.label, "A")
        XCTAssertNil(store.participants.first?.accountID)
        XCTAssertEqual(service.fetchCount, 2)
    }

    @MainActor
    func testRosterEditPreservesIdentityAndAccountWhileDeactivating() async {
        let service = TestRosterService()
        let original = service.row(accountID: UUID())
        service.rows = [original]
        let store = service.store()
        await store.load()
        let success = await store.save(participantID: original.id, displayName: "수정", label: "", isActive: false)
        XCTAssertTrue(success)
        XCTAssertEqual(store.participants.first?.id, original.id)
        XCTAssertEqual(store.participants.first?.accountID, original.accountID)
        XCTAssertEqual(store.participants.first?.isActive, false)
        let restored = await store.save(participantID: original.id, displayName: "수정", label: "복귀", isActive: true)
        XCTAssertTrue(restored)
        XCTAssertEqual(store.participants.first?.isActive, true)
    }

    @MainActor
    func testRosterRejectsUnknownEditAndInvalidName() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        let unknown = await store.save(participantID: UUID(), displayName: "선수", label: "", isActive: true)
        let invalid = await store.save(participantID: nil, displayName: " ", label: "", isActive: true)
        XCTAssertFalse(unknown)
        XCTAssertFalse(invalid)
        XCTAssertTrue(service.commands.isEmpty)
    }

    @MainActor
    func testRosterRetryAfterLostResponseReusesRequestWithoutDuplicate() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        service.fetchFails = true
        let failed = await store.save(participantID: nil, displayName: "선수", label: "A", isActive: true)
        XCTAssertFalse(failed)
        XCTAssertTrue(store.participants.isEmpty)
        service.fetchFails = false
        let success = await store.save(participantID: nil, displayName: " 선수 ", label: " A ", isActive: true)
        XCTAssertTrue(success)
        XCTAssertEqual(service.commands[0], service.commands[1])
        XCTAssertEqual(service.rows.count, 1)
    }

    @MainActor
    func testRosterChangedPayloadUsesDifferentRequest() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        service.saveFails = true
        _ = await store.save(participantID: nil, displayName: "선수", label: "A", isActive: true)
        _ = await store.save(participantID: nil, displayName: "선수", label: "B", isActive: true)
        XCTAssertNotEqual(service.commands[0].requestID, service.commands[1].requestID)
    }

    @MainActor
    func testRosterMissingAcknowledgedRowIsNotSuccess() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        service.omitSavedRow = true
        let success = await store.save(participantID: nil, displayName: "선수", label: "", isActive: true)
        XCTAssertFalse(success)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testRosterWrongEditReceiptIsRejected() async {
        let service = TestRosterService()
        let row = service.row()
        service.rows = [row]
        let store = service.store()
        await store.load()
        service.wrongReceipt = true
        let success = await store.save(participantID: row.id, displayName: "수정", label: "", isActive: true)
        XCTAssertFalse(success)
        XCTAssertEqual(service.fetchCount, 1)
    }

    @MainActor
    func testRosterCancellationDoesNotPublishSavedRows() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        service.onSave = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await store.save(participantID: nil, displayName: "선수", label: "", isActive: true) }
        let success = await task.value
        service.onSave = nil
        XCTAssertFalse(success)
        XCTAssertTrue(store.participants.isEmpty)
        XCTAssertFalse(store.isBusy)
    }

    @MainActor
    func testRosterSuppressesConcurrentWritesAndReads() async {
        let service = TestRosterService()
        let store = service.store()
        await store.load()
        service.onSave = {
            let duplicate = await store.save(participantID: nil, displayName: "중복", label: "", isActive: true)
            XCTAssertFalse(duplicate)
            await store.load()
        }
        let success = await store.save(participantID: nil, displayName: "선수", label: "", isActive: true)
        service.onSave = nil
        XCTAssertTrue(success)
        XCTAssertEqual(service.commands.count, 1)
        XCTAssertEqual(service.fetchCount, 2)
    }

    @MainActor
    func testClubEmptyListIsNotAnError() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.memberships, [])
        XCTAssertNil(store.selectedMembership)
    }

    @MainActor
    func testClubConfigurationFailureKeepsListLocked() async {
        let store = ClubStore(accountID: UUID()) { throw ClubError.invalidMembership }
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertEqual(store.memberships, [])
        XCTAssertEqual(store.isBusy, false)
        let success = await store.create(name: "동호회", description: "")
        XCTAssertEqual(success, false)
    }

    @MainActor
    func testClubClosedOwnerCannotManage() {
        let service = TestClubService()
        let entry = service.entry()
        let closed = Club(id: entry.id, name: entry.club.name, description: "", ownerAccountID: service.accountID, status: .closed, legacyID: nil)
        XCTAssertEqual(ClubMembership(membership: entry.membership, club: closed).canManage, false)
    }

    @MainActor
    func testClubLoadFailureCanBeRetried() async {
        let service = TestClubService()
        service.fetchShouldFail = true
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertTrue(store.errorMessage != nil)
        service.fetchShouldFail = false
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testClubSelectionKeepsRolesSeparate() async {
        let service = TestClubService()
        let owner = service.entry(role: .owner)
        let member = service.entry(role: .member)
        service.entries = [owner, member]
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        store.select(clubID: owner.id)
        XCTAssertEqual(store.selectedMembership?.canManage, true)
        store.select(clubID: member.id)
        XCTAssertEqual(store.selectedMembership?.canManage, false)
        XCTAssertEqual(store.selectedMembership?.id, member.id)
        store.select(clubID: UUID())
        XCTAssertEqual(store.selectedMembership?.id, member.id)
        store.select(clubID: nil)
        XCTAssertNil(store.selectedMembership)
    }

    @MainActor
    func testClubRefreshFailureRemovesPreviousSelection() async {
        let service = TestClubService()
        let entry = service.entry()
        service.entries = [entry]
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        store.select(clubID: entry.id)
        service.fetchShouldFail = true
        await store.load()
        XCTAssertNil(store.selectedMembership)
        XCTAssertEqual(store.memberships, [])
        XCTAssertEqual(store.state, .unavailable)
    }

    @MainActor
    func testClubRejectsPendingAndOtherAccountMemberships() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        service.entries = [service.entry(status: .pending)]
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        service.entries = [service.entry(accountID: UUID())]
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertEqual(store.memberships, [])
    }

    @MainActor
    func testClubRejectsDuplicateOrMismatchedClubIDs() async {
        let service = TestClubService()
        let entry = service.entry()
        let store = ClubStore(accountID: service.accountID) { service }
        service.entries = [entry, entry]
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        service.entries = [ClubMembership(membership: entry.membership, club: service.entry().club)]
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
    }

    func testClubCommandValidatesAndEncodesContract() throws {
        let requestID = UUID()
        let command = try CreateClubCommand(name: " 우리 리그\n", description: " 소개 ", requestID: requestID)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        let payload = try XCTUnwrap(encoded["payload"] as? [String: Any])
        XCTAssertEqual(encoded["operation"] as? String, "create_club")
        XCTAssertEqual(encoded["request_id"] as? String, requestID.uuidString)
        XCTAssertEqual(payload["name"] as? String, "우리 리그")
        XCTAssertEqual(payload["description"] as? String, "소개")
        XCTAssertNil(payload["owner_account_id"])
        XCTAssertEqual(try CreateClubCommand(name: String(repeating: "가", count: 100), description: "").payload.name.unicodeScalars.count, 100)
        XCTAssertThrowsError(try CreateClubCommand(name: " \n ", description: "")) { _ in }
        XCTAssertThrowsError(try CreateClubCommand(name: String(repeating: "가", count: 101), description: "")) { _ in }
        XCTAssertThrowsError(try CreateClubCommand(name: String(repeating: "e\u{301}", count: 51), description: "")) { _ in }
    }

    func testClubMembershipDecodesJoinedResponse() throws {
        let accountID = UUID()
        let clubID = UUID()
        let json = """
        {"id":"\(UUID())","club_id":"\(clubID)","account_id":"\(accountID)","role":"owner","status":"approved",
        "club":{"id":"\(clubID)","name":"테니스","description":"소개","owner_account_id":"\(accountID)","status":"active","legacy_id":null}}
        """
        let entry = try JSONDecoder().decode(ClubMembership.self, from: Data(json.utf8))
        XCTAssertEqual(entry.id, clubID)
        XCTAssertEqual(entry.membership.accountID, accountID)
        XCTAssertEqual(entry.canManage, true)
        XCTAssertThrowsError(try JSONDecoder().decode(ClubMembership.self, from: Data(json.replacingOccurrences(of: "\"club\":{", with: "\"hidden_club\":{").utf8))) { _ in }
    }

    @MainActor
    func testClubCreationRequiresAcknowledgedOwnerMembership() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.onCreate = {
            XCTAssertNil(store.selectedMembership)
            XCTAssertEqual(store.isBusy, true)
        }
        let success = await store.create(name: " 동호회 ", description: "소개")
        XCTAssertEqual(success, true)
        XCTAssertEqual(store.selectedMembership?.club.name, "동호회")
        XCTAssertEqual(store.selectedMembership?.canManage, true)
        XCTAssertEqual(service.fetchCount, 2)
        XCTAssertEqual(store.isBusy, false)
    }

    @MainActor
    func testClubInvalidNameDoesNotCallServer() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        let success = await store.create(name: " ", description: "")
        XCTAssertEqual(success, false)
        XCTAssertEqual(service.commands.count, 0)
        XCTAssertTrue(store.errorMessage != nil)
    }

    @MainActor
    func testClubCreateFailureReusesRequestID() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.createShouldFail = true
        let failed = await store.create(name: "동호회", description: "소개")
        service.createShouldFail = false
        let success = await store.create(name: " 동호회 ", description: "소개")
        XCTAssertEqual(failed, false)
        XCTAssertEqual(success, true)
        XCTAssertEqual(service.commands.count, 2)
        XCTAssertEqual(service.commands[0], service.commands[1])
    }

    @MainActor
    func testClubChangedPayloadUsesNewRequestID() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.createShouldFail = true
        _ = await store.create(name: "동호회", description: "이전")
        _ = await store.create(name: "동호회", description: "변경")
        XCTAssertNotEqual(service.commands[0].requestID, service.commands[1].requestID)
    }

    @MainActor
    func testClubReadFailureAfterCreateKeepsRetryID() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.onCreate = { service.fetchShouldFail = true }
        let failed = await store.create(name: "동호회", description: "")
        XCTAssertEqual(failed, false)
        XCTAssertNil(store.selectedMembership)
        service.onCreate = nil
        service.fetchShouldFail = false
        let success = await store.create(name: "동호회", description: "")
        XCTAssertEqual(success, true)
        XCTAssertEqual(service.commands[0].requestID, service.commands[1].requestID)
        XCTAssertEqual(service.entries.count, 1)
    }

    @MainActor
    func testClubCreateRejectsUnexpectedOwner() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.returnWrongOwner = true
        let success = await store.create(name: "동호회", description: "")
        XCTAssertEqual(success, false)
        XCTAssertNil(store.selectedMembership)
    }

    @MainActor
    func testClubCreationRejectsMissingOwnerMembership() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.omitCreatedMembership = true
        let success = await store.create(name: "동호회", description: "")
        XCTAssertEqual(success, false)
        XCTAssertNil(store.selectedMembership)
        XCTAssertTrue(store.errorMessage != nil)
    }

    @MainActor
    func testCancelledClubLoadDoesNotPublishMemberships() async {
        let service = TestClubService()
        service.entries = [service.entry()]
        service.onFetch = { withUnsafeCurrentTask { $0?.cancel() } }
        let store = ClubStore(accountID: service.accountID) { service }
        let task = Task { await store.load() }
        await task.value
        XCTAssertEqual(store.memberships, [])
        XCTAssertEqual(store.isBusy, false)
        service.onFetch = nil
        await store.load()
        XCTAssertEqual(store.memberships, service.entries)
    }

    @MainActor
    func testClubCreateSuppressesConcurrentCommands() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.onCreate = {
            let duplicate = await store.create(name: "중복", description: "")
            XCTAssertEqual(duplicate, false)
            await store.load()
        }
        _ = await store.create(name: "동호회", description: "")
        service.onCreate = nil
        XCTAssertEqual(service.commands.count, 1)
        XCTAssertEqual(service.fetchCount, 2)
    }

    @MainActor
    func testCancelledClubCreationDoesNotSelectClub() async {
        let service = TestClubService()
        let store = ClubStore(accountID: service.accountID) { service }
        await store.load()
        service.onCreate = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await store.create(name: "동호회", description: "") }
        let success = await task.value
        service.onCreate = nil
        XCTAssertEqual(success, false)
        XCTAssertNil(store.selectedMembership)
        XCTAssertEqual(store.isBusy, false)
    }

    @MainActor
    func testMissingProfileRequiresNickname() async {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        XCTAssertEqual(store.state, .needsName)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testExistingProfileEntersApp() async {
        let service = TestProfileService()
        let profile = AccountProfile(id: service.accountID, displayName: "기존 회원")
        service.profile = profile
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        XCTAssertEqual(store.state, .ready(profile))
    }

    @MainActor
    func testProfileLoadFailureDoesNotStartOnboarding() async {
        let service = TestProfileService()
        service.shouldFail = true
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertTrue(store.errorMessage != nil)
        await store.save(displayName: "회원")
        XCTAssertEqual(service.commands.count, 0)
        service.shouldFail = false
        await store.load()
        XCTAssertEqual(store.state, .needsName)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testProfileConfigurationFailureKeepsAppLocked() async {
        let store = ProfileStore(accountID: UUID()) { throw ProfileError.unexpectedAccount }
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertEqual(store.isBusy, false)
    }

    @MainActor
    func testProfileRejectsAnotherAccountsData() async {
        let service = TestProfileService()
        service.profile = AccountProfile(id: UUID(), displayName: "다른 회원")
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        XCTAssertEqual(store.state, .unavailable)
    }

    func testProfileCommandTrimsAndEncodesRPCContract() throws {
        let requestID = UUID()
        let command = try SaveProfileCommand(displayName: " \n회원\t ", requestID: requestID)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        let payload = try XCTUnwrap(encoded["payload"] as? [String: Any])
        XCTAssertEqual(encoded["operation"] as? String, "save_profile")
        XCTAssertEqual(encoded["request_id"] as? String, requestID.uuidString)
        XCTAssertEqual(payload["display_name"] as? String, "회원")
        XCTAssertNil(payload["id"])
    }

    func testProfileNicknameUsesDatabaseUnicodeLength() throws {
        XCTAssertEqual(try SaveProfileCommand(displayName: "가").payload.displayName, "가")
        XCTAssertEqual(try SaveProfileCommand(displayName: String(repeating: "가", count: 40)).payload.displayName.unicodeScalars.count, 40)
        XCTAssertThrowsError(try SaveProfileCommand(displayName: String(repeating: "가", count: 41))) { _ in }
        XCTAssertThrowsError(try SaveProfileCommand(displayName: String(repeating: "e\u{301}", count: 21))) { _ in }
        XCTAssertThrowsError(try SaveProfileCommand(displayName: " \n\t ")) { _ in }
    }

    @MainActor
    func testInvalidNicknameDoesNotCallServer() async {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        await store.save(displayName: "   ")
        await store.save(displayName: String(repeating: "가", count: 41))
        XCTAssertEqual(service.commands.count, 0)
        XCTAssertEqual(store.state, .needsName)
        XCTAssertTrue(store.errorMessage != nil)
    }

    @MainActor
    func testProfileEntersAppOnlyAfterSaveAcknowledgement() async {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        service.onSave = {
            XCTAssertEqual(store.state, .needsName)
            XCTAssertEqual(store.isBusy, true)
        }
        await store.save(displayName: " 회원 ")
        XCTAssertEqual(store.state, .ready(AccountProfile(id: service.accountID, displayName: "회원")))
        XCTAssertEqual(store.isBusy, false)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testProfileSaveFailureReusesRequestIDForSameNickname() async throws {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        service.shouldFail = true
        await store.save(displayName: "회원")
        XCTAssertEqual(store.state, .needsName)
        XCTAssertTrue(store.errorMessage != nil)
        service.shouldFail = false
        await store.save(displayName: " 회원 ")
        XCTAssertEqual(service.commands.count, 2)
        XCTAssertEqual(service.commands[0], service.commands[1])
        XCTAssertEqual(store.state, .ready(AccountProfile(id: service.accountID, displayName: "회원")))
    }

    @MainActor
    func testChangedNicknameUsesNewRequestID() async {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        service.shouldFail = true
        await store.save(displayName: "이전 이름")
        await store.save(displayName: "새 이름")
        XCTAssertEqual(service.commands.count, 2)
        XCTAssertNotEqual(service.commands[0].requestID, service.commands[1].requestID)
    }

    @MainActor
    func testProfilePreventsConcurrentSaveAndLoad() async {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        service.onSave = {
            await store.save(displayName: "중복")
            await store.load()
        }
        await store.save(displayName: "회원")
        service.onSave = nil
        XCTAssertEqual(service.commands.count, 1)
        XCTAssertEqual(service.fetchCount, 1)
    }

    @MainActor
    func testProfileRejectsMismatchedSaveResponse() async {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        service.savedAccountID = UUID()
        await store.save(displayName: "회원")
        XCTAssertEqual(store.state, .needsName)
        XCTAssertTrue(store.errorMessage != nil)
    }

    @MainActor
    func testCancelledProfileSaveDoesNotEnterApp() async {
        let service = TestProfileService()
        let store = ProfileStore(accountID: service.accountID) { service }
        await store.load()
        service.onSave = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await store.save(displayName: "회원") }
        await task.value
        service.onSave = nil
        XCTAssertEqual(store.state, .needsName)
        XCTAssertEqual(store.isBusy, false)
    }

    @MainActor
    func testCancelledProfileLoadDoesNotEnterApp() async {
        let service = TestProfileService()
        let profile = AccountProfile(id: service.accountID, displayName: "회원")
        service.profile = profile
        service.onFetch = { withUnsafeCurrentTask { $0?.cancel() } }
        let store = ProfileStore(accountID: service.accountID) { service }
        let task = Task { await store.load() }
        await task.value
        XCTAssertEqual(store.state, .loading)
        XCTAssertEqual(store.isBusy, false)
        service.onFetch = nil
        await store.load()
        XCTAssertEqual(store.state, .ready(profile))
    }

    @MainActor
    func testAuthRestoresSignedInAccount() async {
        let service = TestAuthService()
        let account = AuthAccount(id: UUID())
        service.updates = [.signedIn(account)]
        let store = AuthStore { service }

        await store.observeSession()

        XCTAssertEqual(store.state, .signedIn(account))
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testAuthClearsAccountWhenSessionEnds() async {
        let service = TestAuthService()
        service.updates = [.signedIn(AuthAccount(id: UUID())), .signedOut]
        let store = AuthStore { service }

        await store.observeSession()

        XCTAssertEqual(store.state, .signedOut)
    }

    @MainActor
    func testAuthRestoreFailureCanBeRetried() async {
        let service = TestAuthService()
        service.updates = [.unavailable]
        let store = AuthStore { service }
        await store.observeSession()
        XCTAssertEqual(store.state, .unavailable)

        service.account = AuthAccount(id: UUID())
        await store.retrySession()

        XCTAssertEqual(store.state, service.account.map(AuthSessionState.signedIn))
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.observationID, 1)
        XCTAssertEqual(store.isBusy, false)
    }

    @MainActor
    func testAuthConfigurationFailureDoesNotEnterApp() async {
        let store = AuthStore {
            throw SupabaseConfigurationError.missingValue("SUPABASE_URL")
        }

        await store.observeSession()

        XCTAssertEqual(store.state, .unavailable)
        XCTAssertTrue(store.errorMessage?.contains("SUPABASE_URL") == true)
    }

    @MainActor
    func testAuthRetryFailureKeepsAppLocked() async {
        let service = TestAuthService()
        service.restoreShouldFail = true
        let store = AuthStore { service }

        await store.retrySession()

        XCTAssertEqual(store.state, .unavailable)
        XCTAssertEqual(store.isBusy, false)
        XCTAssertTrue(store.errorMessage != nil)
    }

    @MainActor
    func testAuthRestoreWithoutSessionShowsLogin() async {
        let service = TestAuthService()
        let store = AuthStore { service }

        await store.retrySession()

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testAppleLoginPassesTokenAndNonceToService() async {
        let service = TestAuthService()
        let store = AuthStore { service }
        await store.observeSession()

        await store.signInWithApple(idToken: "test-id-token", nonce: "test-raw-nonce")

        XCTAssertEqual(service.receivedToken, "test-id-token")
        XCTAssertEqual(service.receivedNonce, "test-raw-nonce")
        XCTAssertEqual(store.state, .signedIn(service.loginAccount))
        XCTAssertEqual(store.isBusy, false)
    }

    @MainActor
    func testAppleLoginRejectsEmptyCredentials() async {
        let service = TestAuthService()
        let store = AuthStore { service }
        await store.observeSession()

        await store.signInWithApple(idToken: "", nonce: "nonce")
        await store.signInWithApple(idToken: "token", nonce: "")

        XCTAssertEqual(service.signInCount, 0)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertTrue(store.errorMessage != nil)
    }

    @MainActor
    func testAppleLoginFailureDoesNotExposeToken() async {
        let service = TestAuthService()
        service.shouldFail = true
        let store = AuthStore { service }
        await store.observeSession()

        await store.signInWithApple(idToken: "private-test-token", nonce: "private-test-nonce")

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(store.isBusy, false)
        XCTAssertTrue(store.errorMessage != nil)
        XCTAssertEqual(store.errorMessage?.contains("private-test"), false)
    }

    @MainActor
    func testAppleLoginPreventsConcurrentRequests() async {
        let service = TestAuthService()
        let store = AuthStore { service }
        await store.observeSession()
        service.onSignIn = {
            await store.signInWithApple(idToken: "duplicate", nonce: "duplicate")
        }

        await store.signInWithApple(idToken: "token", nonce: "nonce")
        service.onSignIn = nil

        XCTAssertEqual(service.signInCount, 1)
    }

    @MainActor
    func testSignOutClearsAccount() async {
        let service = TestAuthService()
        service.updates = [.signedIn(service.loginAccount)]
        let store = AuthStore { service }
        await store.observeSession()

        await store.signOut()

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(service.signOutCount, 1)
        XCTAssertEqual(store.isBusy, false)
    }

    @MainActor
    func testSignOutFailureAfterLocalRemovalStillClearsAccount() async {
        let service = TestAuthService()
        service.updates = [.signedIn(service.loginAccount)]
        service.shouldFail = true
        let store = AuthStore { service }
        await store.observeSession()

        await store.signOut()

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertTrue(store.errorMessage != nil)
    }

    func testAppleNonceHashUsesSHA256() {
        let nonce = AppleSignInNonce(rawValue: "abc")
        XCTAssertEqual(nonce.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testAppleNonceIsRandomHex() throws {
        let first = try AppleSignInNonce.generate()
        let second = try AppleSignInNonce.generate()
        XCTAssertEqual(first.rawValue.count, 64)
        XCTAssertEqual(first.sha256.count, 64)
        XCTAssertTrue(first.rawValue.allSatisfy { $0.isHexDigit })
        XCTAssertNotEqual(first.rawValue, second.rawValue)
    }

    func testSupabaseConfigurationLoadsPublishableKey() throws {
        let configuration = try SupabaseConfiguration(infoDictionary: [
            "SUPABASE_URL": " https://dwvogajwqeodwkjppdyw.supabase.co \n",
            "SUPABASE_PUBLISHABLE_KEY": " sb_publishable_configuration_test \n"
        ])

        XCTAssertEqual(configuration.url.absoluteString, "https://dwvogajwqeodwkjppdyw.supabase.co")
        XCTAssertEqual(configuration.publishableKey, "sb_publishable_configuration_test")
    }

    func testSupabaseConfigurationRejectsMissingURL() {
        XCTAssertThrowsError(try SupabaseConfiguration(infoDictionary: [:])) { error in
            XCTAssertEqual(error as? SupabaseConfigurationError, .missingValue("SUPABASE_URL"))
        }
    }

    func testSupabaseConfigurationRejectsMissingKey() {
        XCTAssertThrowsError(try SupabaseConfiguration(infoDictionary: [
            "SUPABASE_URL": "https://dwvogajwqeodwkjppdyw.supabase.co"
        ])) { error in
            XCTAssertEqual(error as? SupabaseConfigurationError, .missingValue("SUPABASE_PUBLISHABLE_KEY"))
        }
    }

    func testSupabaseConfigurationRejectsPlaceholderKeys() {
        for key in ["", "  ", "$(SUPABASE_PUBLISHABLE_KEY)", "YOUR_SUPABASE_PUBLISHABLE_KEY", "sb_publishable_REPLACE_ME"] {
            XCTAssertThrowsError(try SupabaseConfiguration(infoDictionary: [
                "SUPABASE_URL": "https://dwvogajwqeodwkjppdyw.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": key
            ])) { error in
                XCTAssertEqual(error as? SupabaseConfigurationError, .missingValue("SUPABASE_PUBLISHABLE_KEY"))
            }
        }
    }

    func testSupabaseConfigurationRejectsInvalidURLs() {
        let invalidURLs = [
            "http://dwvogajwqeodwkjppdyw.supabase.co",
            "https://",
            "not-a-url",
            "https://user:password@example.com",
            "https://example.com/rest/v1",
            "https://example.com?token=test",
            "https://example.com#fragment",
            "https://example.com:8443"
        ]
        for url in invalidURLs {
            XCTAssertThrowsError(try SupabaseConfiguration(infoDictionary: [
                "SUPABASE_URL": url,
                "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_configuration_test"
            ])) { error in
                XCTAssertEqual(error as? SupabaseConfigurationError, .invalidURL)
            }
        }
    }

    func testSupabaseConfigurationLoadsLegacyAnonKey() throws {
        let payload = Data("{\"role\":\"anon\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let key = "eyJhbGciOiJIUzI1NiJ9.\(payload).test_signature"
        let configuration = try SupabaseConfiguration(infoDictionary: [
            "SUPABASE_URL": "https://dwvogajwqeodwkjppdyw.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": key
        ])
        XCTAssertEqual(configuration.publishableKey, key)
    }

    func testSupabaseConfigurationRejectsPrivilegedAndMalformedKeys() {
        for key in ["sb_secret_configuration_test", "eyJhbGciOiJIUzI1NiJ9.test.signature", "service_role", "sb_publishable_invalid key"] {
            XCTAssertThrowsError(try SupabaseConfiguration(infoDictionary: [
                "SUPABASE_URL": "https://dwvogajwqeodwkjppdyw.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": key
            ])) { error in
                XCTAssertEqual(error as? SupabaseConfigurationError, .invalidPublishableKey)
            }
        }
    }

    func testSupabaseConfigurationRejectsLegacyServiceRoleKey() {
        let payload = Data("{\"role\":\"service_role\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try SupabaseConfiguration(infoDictionary: [
            "SUPABASE_URL": "https://dwvogajwqeodwkjppdyw.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "eyJhbGciOiJIUzI1NiJ9.\(payload).test_signature"
        ])) { error in
            XCTAssertEqual(error as? SupabaseConfigurationError, .invalidPublishableKey)
        }
    }

    func testMembershipKeepsClubSpecificRole() throws {
        let accountID = UUID()
        let owner = Membership(id: UUID(), clubID: UUID(), accountID: accountID, role: .owner, status: .approved)
        let member = Membership(id: UUID(), clubID: UUID(), accountID: accountID, role: .member, status: .pending)
        let decoded = try JSONDecoder().decode([Membership].self, from: JSONEncoder().encode([owner, member]))

        XCTAssertEqual(decoded[0].accountID, decoded[1].accountID)
        XCTAssertNotEqual(decoded[0].clubID, decoded[1].clubID)
        XCTAssertEqual(decoded[0].role, .owner)
        XCTAssertEqual(decoded[1].status, .pending)
    }

    func testMigratedSessionKeepsUnknownTimes() throws {
        let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","club_id":"00000000-0000-0000-0000-000000000002",
        "title":"이관 모임","starts_at":null,"ends_at":null,"location":null,"capacity":16,"court_count":1,
        "round_count":3,"attendance_deadline":null,"notice":"","status":"needs_review","roster_version":1,
        "schedule_version":0,"schedule_stale":true,"seed":null}
        """.utf8)
        let session = try JSONDecoder().decode(LeagueSession.self, from: data)

        XCTAssertEqual(session.status, .needsReview)
        XCTAssertNil(session.startsAt)
        XCTAssertNil(session.endsAt)
        XCTAssertTrue(session.scheduleStale)
    }

    func testZeroMatchesHasNoWinRate() throws {
        let data = Data("""
        {"club_id":"00000000-0000-0000-0000-000000000001","participant_id":"00000000-0000-0000-0000-000000000002",
        "display_name":"동명이인","wins":0,"losses":0,"completed_matches":0,"appearances":1,"win_rate":null}
        """.utf8)
        let stats = try JSONDecoder().decode(ParticipantStats.self, from: data)

        XCTAssertNil(stats.winRate)
        XCTAssertEqual(stats.appearances, 1)
        XCTAssertEqual(stats.completedMatches, 0)
    }

    func testWinnerCanBeRecordedWithoutScore() throws {
        let data = Data("""
        {"match_id":"00000000-0000-0000-0000-000000000001","winner":"b","score_a":null,"score_b":null,
        "version":2,"is_valid":true}
        """.utf8)
        let result = try JSONDecoder().decode(MatchResult.self, from: data)

        XCTAssertEqual(result.winner, .b)
        XCTAssertEqual(result.version, 2)
        XCTAssertNil(result.scoreA)
        XCTAssertNil(result.scoreB)
    }

    func testGuestHasNoAccountOrClubParticipant() throws {
        let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","session_id":"00000000-0000-0000-0000-000000000002",
        "club_participant_id":null,"account_id":null,"display_name":"게스트","response":"attending","approval":"pending"}
        """.utf8)
        let guest = try JSONDecoder().decode(SessionParticipant.self, from: data)

        XCTAssertNil(guest.accountID)
        XCTAssertNil(guest.clubParticipantID)
        XCTAssertEqual(guest.approval, .pending)
    }

    func testParticipantIdentitySurvivesNameChange() throws {
        let participantID = UUID()
        let clubID = UUID()
        let before = ClubParticipant(id: participantID, clubID: clubID, accountID: nil,
                                     displayName: "이전 이름", label: nil, isActive: true, legacyPlayerID: 1)
        let after = ClubParticipant(id: participantID, clubID: clubID, accountID: nil,
                                    displayName: "새 이름", label: nil, isActive: true, legacyPlayerID: 1)

        XCTAssertEqual(before.id, after.id)
        XCTAssertNotEqual(before.displayName, after.displayName)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? [String: Any])
        XCTAssertEqual(encoded["display_name"] as? String, "새 이름")
        XCTAssertEqual(encoded["legacy_player_id"] as? Int, 1)
    }

}

@MainActor
private final class TestRosterService: LeagueRosterService {
    let accountID = UUID()
    let clubID = UUID()
    var rows: [ClubParticipant] = []
    var commands: [SaveParticipantCommand] = []
    var fetchCount = 0
    var fetchFails = false
    var saveFails = false
    var omitSavedRow = false
    var wrongReceipt = false
    var onSave: (() async -> Void)?
    private var receipts: [UUID: UUID] = [:]

    func store(role: MembershipRole = .owner, status: MembershipStatus = .approved, clubStatus: ClubStatus = .active) -> ClubRosterStore {
        let club = Club(id: clubID, name: "동호회", description: "", ownerAccountID: accountID, status: clubStatus, legacyID: nil)
        let membership = Membership(id: UUID(), clubID: clubID, accountID: accountID, role: role, status: status)
        return ClubRosterStore(membership: ClubMembership(membership: membership, club: club)) { self }
    }

    func row(name: String = "선수", active: Bool = true, clubID: UUID? = nil, accountID: UUID? = nil) -> ClubParticipant {
        ClubParticipant(id: UUID(), clubID: clubID ?? self.clubID, accountID: accountID, displayName: name, label: "기존", isActive: active, legacyPlayerID: nil)
    }

    func fetchParticipants(clubID: UUID, accountID: UUID) async throws -> [ClubParticipant] {
        XCTAssertEqual(clubID, self.clubID)
        XCTAssertEqual(accountID, self.accountID)
        fetchCount += 1
        if fetchFails { throw RosterError.invalidResponse }
        return rows
    }

    func saveParticipant(_ command: SaveParticipantCommand, accountID: UUID) async throws -> UUID {
        XCTAssertEqual(accountID, self.accountID)
        XCTAssertEqual(command.payload.clubID, clubID)
        commands.append(command)
        await onSave?()
        if saveFails { throw RosterError.invalidResponse }
        if let saved = receipts[command.requestID] { return saved }
        let payload = command.payload
        let savedID = payload.participantID ?? UUID()
        let old = rows.first { $0.id == savedID }
        let updated = ClubParticipant(id: savedID, clubID: payload.clubID, accountID: old?.accountID,
                                      displayName: payload.displayName, label: payload.label,
                                      isActive: payload.isActive ?? true, legacyPlayerID: old?.legacyPlayerID)
        if !omitSavedRow {
            rows.removeAll { $0.id == savedID }
            rows.append(updated)
        }
        receipts[command.requestID] = savedID
        return wrongReceipt ? UUID() : savedID
    }
}

@MainActor
private final class TestClubService: LeagueClubService {
    let accountID = UUID()
    var entries: [ClubMembership] = []
    var commands: [CreateClubCommand] = []
    var fetchCount = 0
    var fetchShouldFail = false
    var createShouldFail = false
    var returnWrongOwner = false
    var omitCreatedMembership = false
    var onFetch: (() -> Void)?
    var onCreate: (() async -> Void)?
    private var receipts: [UUID: Club] = [:]

    func entry(role: MembershipRole = .owner, status: MembershipStatus = .approved, accountID: UUID? = nil) -> ClubMembership {
        let actor = accountID ?? self.accountID
        let club = Club(id: UUID(), name: "테니스", description: "소개", ownerAccountID: role == .owner ? actor : UUID(), status: .active, legacyID: nil)
        return ClubMembership(membership: Membership(id: UUID(), clubID: club.id, accountID: actor, role: role, status: status), club: club)
    }

    func fetchMemberships(accountID: UUID) async throws -> [ClubMembership] {
        fetchCount += 1
        onFetch?()
        if fetchShouldFail { throw ClubError.invalidMembership }
        return entries
    }

    func createClub(_ command: CreateClubCommand, accountID: UUID) async throws -> Club {
        commands.append(command)
        await onCreate?()
        if createShouldFail { throw ClubError.unexpectedOwner }
        if let club = receipts[command.requestID] { return club }
        let club = Club(id: UUID(), name: command.payload.name, description: command.payload.description, ownerAccountID: returnWrongOwner ? UUID() : accountID, status: .active, legacyID: nil)
        receipts[command.requestID] = club
        if !omitCreatedMembership {
            entries.append(ClubMembership(membership: Membership(id: UUID(), clubID: club.id, accountID: accountID, role: .owner, status: .approved), club: club))
        }
        return club
    }
}

@MainActor
private final class TestProfileService: LeagueProfileService {
    let accountID = UUID()
    var profile: AccountProfile?
    var savedAccountID: UUID?
    var shouldFail = false
    var commands: [SaveProfileCommand] = []
    var fetchCount = 0
    var onSave: (() async -> Void)?
    var onFetch: (() -> Void)?

    func fetchProfile(accountID: UUID) async throws -> AccountProfile? {
        fetchCount += 1
        onFetch?()
        if shouldFail { throw ProfileError.unexpectedAccount }
        return profile
    }

    func saveProfile(_ command: SaveProfileCommand, accountID: UUID) async throws -> AccountProfile {
        commands.append(command)
        await onSave?()
        if shouldFail { throw ProfileError.unexpectedAccount }
        return AccountProfile(id: savedAccountID ?? accountID, displayName: command.payload.displayName)
    }
}

@MainActor
private final class TestAuthService: LeagueAuthService {
    let loginAccount = AuthAccount(id: UUID())
    var account: AuthAccount?
    var updates: [AuthSessionState] = [.signedOut]
    var shouldFail = false
    var restoreShouldFail = false
    var signInCount = 0
    var signOutCount = 0
    var receivedToken: String?
    var receivedNonce: String?
    var onSignIn: (() async -> Void)?

    func sessionUpdates() -> AsyncStream<AuthSessionState> {
        AsyncStream { continuation in
            for update in updates { continuation.yield(update) }
            continuation.finish()
        }
    }

    func restoreSession() async throws -> AuthAccount? {
        if restoreShouldFail { throw TestError.unavailable }
        return account
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthAccount {
        signInCount += 1
        receivedToken = idToken
        receivedNonce = nonce
        if shouldFail { throw TestError.unavailable }
        await onSignIn?()
        account = loginAccount
        return loginAccount
    }

    func signOut() async throws {
        signOutCount += 1
        account = nil
        if shouldFail { throw TestError.unavailable }
    }

    private enum TestError: Error {
        case unavailable
    }
}
