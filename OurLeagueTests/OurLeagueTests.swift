//
//  OurLeagueTests.swift
//  OurLeagueTests
//
//  Created by 양호준 on 2023/12/12.
//

import XCTest
@testable import OurLeague

final class OurLeagueTests: XCTestCase {

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
