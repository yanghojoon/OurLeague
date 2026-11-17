//
//  LoginView.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/16.
//

import AuthenticationServices
import SwiftUI

@MainActor
struct LoginView: View {
    @ObservedObject var authStore: AuthStore
    @State private var nonce: AppleSignInNonce?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "tennis.racket.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("OurLeague")
                    .font(.largeTitle.bold())
                Text("함께 치고, 함께 기록하세요.")
                    .font(.title2.bold())
                Text("로그인하고 우리 클럽의 모임과 경기 기록을 관리하세요.")
                    .foregroundStyle(.secondary)

                SignInWithAppleButton(.signIn) { request in
                    do {
                        let nonce = try AppleSignInNonce.generate()
                        self.nonce = nonce
                        request.requestedScopes = [.email]
                        request.nonce = nonce.sha256
                    } catch {
                        nonce = nil
                        authStore.showAppleSignInError()
                    }
                } onCompletion: { result in
                    let currentNonce = nonce
                    nonce = nil
                    switch result {
                    case .success(let authorization):
                        guard let currentNonce,
                              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let tokenData = credential.identityToken,
                              let idToken = String(data: tokenData, encoding: .utf8) else {
                            authStore.showAppleSignInError()
                            return
                        }
                        Task {
                            await authStore.signInWithApple(idToken: idToken, nonce: currentNonce.rawValue)
                        }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            authStore.showAppleSignInError()
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .disabled(authStore.isBusy || nonce != nil)
                .accessibilityIdentifier("appleSignInButton")

                if authStore.isBusy {
                    ProgressView("로그인 중…")
                }
                if let message = authStore.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("authErrorMessage")
                }
                Text("처음 로그인하면 계정이 생성됩니다. 클럽 가입과 승인은 로그인 후 별도로 진행됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(28)
            .padding(.top, 64)
            .frame(maxWidth: .infinity)
        }
        .background(Color.green.opacity(0.05).ignoresSafeArea())
    }
}
