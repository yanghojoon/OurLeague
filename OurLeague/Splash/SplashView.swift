//
//  SplashView.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import SwiftUI

@MainActor
struct SplashView: View {
    @ObservedObject var authStore: AuthStore
    @State private var showsSignOutConfirmation = false

    var body: some View {
        Group {
            switch authStore.state {
            case .restoring:
                ProgressView("로그인 상태 확인 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                LoginView(authStore: authStore)
            case .signedIn(let account):
                NavigationStack {
                    ProfileGateView(accountID: account.id)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("로그아웃") {
                                    showsSignOutConfirmation = true
                                }
                                .disabled(authStore.isBusy)
                                .accessibilityIdentifier("signOutButton")
                            }
                        }
                        .safeAreaInset(edge: .bottom) {
                            if let message = authStore.errorMessage {
                                Text(message)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                                    .padding()
                                    .background(.regularMaterial)
                            }
                        }
                }
                .id(account.id)
                .confirmationDialog("이 기기에서 로그아웃할까요?", isPresented: $showsSignOutConfirmation) {
                    Button("로그아웃", role: .destructive) {
                        Task { await authStore.signOut() }
                    }
                    Button("취소", role: .cancel) { }
                }
            case .unavailable:
                ContentUnavailableView {
                    Label("로그인 상태 확인 필요", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(authStore.errorMessage ?? "연결 상태를 확인하고 다시 시도하세요.")
                } actions: {
                    Button("다시 시도") {
                        Task { await authStore.retrySession() }
                    }
                    .disabled(authStore.isBusy)
                }
            }
        }
        .task(id: authStore.observationID) { await authStore.observeSession() }
    }
}
