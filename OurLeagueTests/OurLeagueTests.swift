//
//  OurLeagueTests.swift
//  OurLeagueTests
//
//  Created by 양호준 on 2023/12/12.
//

import XCTest
@testable import OurLeague

final class OurLeagueTests: XCTestCase {

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
