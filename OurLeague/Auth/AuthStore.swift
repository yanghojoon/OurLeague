//
//  AuthStore.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/16.
//

import Combine
import Foundation

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var state: AuthSessionState = .restoring
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var observationID = 0

    private let makeService: () throws -> any LeagueAuthService
    private var service: (any LeagueAuthService)?
    private var isObserving = false

    init(makeService: @escaping () throws -> any LeagueAuthService) {
        self.makeService = makeService
    }

    func observeSession() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        do {
            let service = try configuredService()
            for await update in service.sessionUpdates() {
                guard !Task.isCancelled else { return }
                state = update
                if update == .unavailable {
                    errorMessage = "로그인 상태를 확인하지 못했습니다. 연결 상태를 확인하고 다시 시도하세요."
                } else {
                    errorMessage = nil
                }
            }
        } catch {
            state = .unavailable
            reportConfigurationOrConnectionError(error)
        }
    }

    func retrySession() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        state = .restoring
        defer { isBusy = false }
        do {
            let account = try await configuredService().restoreSession()
            state = account.map(AuthSessionState.signedIn) ?? .signedOut
            if !isObserving { observationID += 1 }
        } catch {
            state = .unavailable
            reportConfigurationOrConnectionError(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        guard !isBusy, state == .signedOut else { return }
        guard !idToken.isEmpty, !nonce.isEmpty else {
            showAppleSignInError()
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let account = try await configuredService().signInWithApple(idToken: idToken, nonce: nonce)
            state = .signedIn(account)
        } catch {
            showAppleSignInError()
        }
    }

    func signOut() async {
        guard !isBusy, case .signedIn = state else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await configuredService().signOut()
            state = .signedOut
        } catch {
            if let service, let account = try? await service.restoreSession() {
                state = .signedIn(account)
            } else {
                state = .signedOut
            }
            errorMessage = "로그아웃 요청을 완료하지 못했습니다. 기기에서 로그아웃됐더라도 서버 세션 만료까지 시간이 걸릴 수 있습니다."
        }
    }

    func showAppleSignInError() {
        errorMessage = "Apple 로그인에 실패했습니다. 연결 상태와 로그인 설정을 확인하고 다시 시도하세요."
    }

    private func configuredService() throws -> any LeagueAuthService {
        if let service { return service }
        let service = try makeService()
        self.service = service
        return service
    }

    private func reportConfigurationOrConnectionError(_ error: Error) {
        if let error = error as? SupabaseConfigurationError {
            errorMessage = error.localizedDescription
        } else {
            errorMessage = "로그인 상태를 확인하지 못했습니다. 연결 상태를 확인하고 다시 시도하세요."
        }
    }
}
