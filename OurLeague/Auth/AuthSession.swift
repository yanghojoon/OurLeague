//
//  AuthSession.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/16.
//

import Foundation

struct AuthAccount: Equatable, Sendable {
    let id: UUID
}

enum AuthSessionState: Equatable, Sendable {
    case restoring
    case signedOut
    case signedIn(AuthAccount)
    case unavailable
}

@MainActor
protocol LeagueAuthService {
    func sessionUpdates() -> AsyncStream<AuthSessionState>
    func restoreSession() async throws -> AuthAccount?
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthAccount
    func signOut() async throws
}
