//
//  ClubListView.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import SwiftUI

@MainActor
struct ClubListView: View {
    @StateObject private var store: ClubStore
    @State private var showsCreation = false
    @State private var reloadID = UUID()

    init(accountID: UUID) {
        _store = StateObject(wrappedValue: ClubStore(accountID: accountID) {
            SupabaseClubService(client: try SupabaseEnvironment.client())
        })
    }

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                ProgressView("내 동호회 확인 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView {
                    Label("동호회 확인 필요", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "잠시 후 다시 시도하세요.")
                } actions: {
                    Button("다시 시도") { reloadID = UUID() }
                }
            case .loaded:
                if let selected = store.selectedMembership {
                    ClubInfoView(membership: selected) { store.select(clubID: nil) }
                } else {
                    clubList
                }
            }
        }
        .task(id: reloadID) { await store.load() }
        .sheet(isPresented: $showsCreation) {
            ClubCreationView(store: store)
        }
        .tint(.green)
    }

    private var clubList: some View {
        List {
            if store.memberships.isEmpty {
                Section {
                    ContentUnavailableView("아직 소속 동호회가 없어요", systemImage: "person.3", description: Text("동호회를 만들고 함께할 준비를 시작하세요."))
                }
            } else {
                Section("승인된 내 소속") {
                    ForEach(store.memberships) { entry in
                        Button {
                            store.select(clubID: entry.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.club.name).font(.headline).foregroundStyle(.primary)
                                    Text(entry.membership.role == .owner ? "운영자" : "회원")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                Button { showsCreation = true } label: {
                    Label("새 동호회 만들기", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("createClubButton")
                Button { reloadID = UUID() } label: {
                    Label("목록 새로고침", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("여러 동호회에 소속될 수 있어요. 가입 신청과 초대 수락은 다음 단계에서 지원합니다.")
            }
        }
        .navigationTitle("내 동호회")
    }
}

@MainActor
private struct ClubCreationView: View {
    @ObservedObject var store: ClubStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var submissionID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("동호회 이름") {
                    TextField("이름 입력 (1~100자)", text: $name)
                        .accessibilityIdentifier("clubNameField")
                }
                Section("소개 (선택)") {
                    TextField("어떤 동호회인가요?", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(.red).font(.callout) }
                }
                Section {
                    Button { submissionID = UUID() } label: {
                        HStack {
                            if store.isBusy { ProgressView() }
                            Text(store.isBusy ? "생성 확인 중…" : "동호회 만들기")
                        }
                    }
                    .disabled((try? CreateClubCommand(name: name, description: description)) == nil)
                    .accessibilityIdentifier("submitClubButton")
                } footer: {
                    Text("생성하면 이 동호회의 운영자로 등록됩니다. 같은 이름의 동호회도 만들 수 있어요.")
                }
            }
            .disabled(store.isBusy)
            .navigationTitle("새 동호회")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.disabled(store.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(store.isBusy)
        .task(id: submissionID) {
            guard submissionID != nil else { return }
            if await store.create(name: name, description: description) { dismiss() }
        }
    }
}
