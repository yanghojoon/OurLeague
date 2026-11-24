//
//  ProfileGateView.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/17.
//

import SwiftUI

@MainActor
struct ProfileGateView: View {
    @StateObject private var store: ProfileStore
    @State private var nickname = ""
    @State private var submissionID: UUID?
    @State private var reloadID = UUID()
    @FocusState private var isNicknameFocused: Bool

    init(accountID: UUID) {
        _store = StateObject(wrappedValue: ProfileStore(accountID: accountID) {
            SupabaseProfileService(client: try SupabaseEnvironment.client())
        })
    }

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                ProgressView("프로필 확인 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsName:
                nicknameForm
            case .ready(let profile):
                ClubListView(accountID: profile.id)
            case .unavailable:
                ContentUnavailableView {
                    Label("프로필 확인 필요", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "잠시 후 다시 시도하세요.")
                } actions: {
                    Button("다시 시도") { reloadID = UUID() }
                        .disabled(store.isBusy)
                }
            }
        }
        .task(id: reloadID) { await store.load() }
        .task(id: submissionID) {
            guard submissionID != nil else { return }
            await store.save(displayName: nickname)
        }
    }

    private var nicknameForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("어떤 이름으로\n함께할까요?")
                    .font(.largeTitle.bold())
                Text("우리 리그에서 사용할 닉네임을 알려주세요.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("닉네임").font(.headline)
                    TextField("닉네임 입력", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isNicknameFocused)
                        .disabled(store.isBusy)
                        .onSubmit(submit)
                        .accessibilityIdentifier("profileNicknameField")
                    Text("앞뒤 공백을 제외하고 1~40자 · 다른 사람과 같은 이름도 가능해요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = store.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("profileErrorMessage")
                }

                Button(action: submit) {
                    HStack {
                        if store.isBusy { ProgressView().tint(.white) }
                        Text(store.isBusy ? "저장 중…" : "시작하기")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(store.isBusy || (try? SaveProfileCommand(displayName: nickname)) == nil)
                .accessibilityIdentifier("saveProfileButton")
            }
            .padding(24)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.green.opacity(0.04).ignoresSafeArea())
        .navigationTitle("프로필 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        guard !store.isBusy else { return }
        isNicknameFocused = false
        submissionID = UUID()
    }
}
