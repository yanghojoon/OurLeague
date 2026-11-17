//
//  SupabaseAuthService.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/16.
//

import Foundation
import Supabase

@MainActor
final class SupabaseAuthService: LeagueAuthService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func sessionUpdates() -> AsyncStream<AuthSessionState> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    guard !Task.isCancelled else { break }
                    if event == .signedOut || event == .userDeleted {
                        continuation.yield(.signedOut)
                    } else if event == .initialSession || session?.isExpired == true {
                        do {
                            let account = try await restoreSession()
                            continuation.yield(account.map(AuthSessionState.signedIn) ?? .signedOut)
                        } catch {
                            continuation.yield(.unavailable)
                        }
                    } else {
                        let account = session.map { AuthAccount(id: $0.user.id) }
                        continuation.yield(account.map(AuthSessionState.signedIn) ?? .signedOut)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func restoreSession() async throws -> AuthAccount? {
        do {
            let session = try await client.auth.session
            return AuthAccount(id: session.user.id)
        } catch AuthError.sessionMissing {
            return nil
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthAccount {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return AuthAccount(id: session.user.id)
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }
}
