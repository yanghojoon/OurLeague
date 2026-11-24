//
//  ClubRosterView.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import SwiftUI

@MainActor
struct ClubRosterView: View {
    @StateObject private var store: ClubRosterStore
    @State private var reloadID = UUID()
    @State private var draft: ParticipantDraft?
    private let clubID: UUID

    init(membership: ClubMembership) {
        clubID = membership.id
        _store = StateObject(wrappedValue: ClubRosterStore(membership: membership) {
            SupabaseRosterService(client: try SupabaseEnvironment.client())
        })
    }

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                ProgressView("명단 확인 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView {
                    Label("명단 확인 필요", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "잠시 후 다시 시도하세요.")
                } actions: {
                    Button("다시 시도") { reloadID = UUID() }
                }
            case .loaded:
                roster
            }
        }
        .navigationTitle("참가자 명단")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadID) { await store.load() }
        .sheet(item: $draft) { selected in
            ParticipantEditorView(store: store, clubID: clubID, draft: selected)
        }
    }

    private var roster: some View {
        List {
            if let message = store.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                }
            }
            if store.participants.isEmpty {
                ContentUnavailableView("아직 등록된 참가자가 없어요", systemImage: "person.2", description: Text("운영자가 정기 참가자를 등록할 수 있어요."))
            }
            participantSection("활동 참가자", active: true)
            participantSection("비활성 참가자", active: false)
            Section {
                if store.canManage {
                    Button { draft = ParticipantDraft(participant: nil) } label: {
                        Label("참가자 추가", systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("addParticipantButton")
                }
                Button { reloadID = UUID() } label: {
                    Label("명단 새로고침", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text(store.canManage
                     ? "이름이 같아도 별도 참가자로 등록됩니다. 보조 라벨로 구분하세요. 비활성화해도 기존 경기 기록은 보존됩니다."
                     : "명단은 조회만 할 수 있습니다. 참가자 등록·수정은 활동 중인 동호회의 운영자만 가능합니다.")
            }
        }
    }

    @ViewBuilder
    private func participantSection(_ title: String, active: Bool) -> some View {
        let entries = store.participants.filter { $0.isActive == active }
        if !entries.isEmpty {
            Section("\(title) · \(entries.count)명") {
                ForEach(entries) { participant in
                    if store.canManage {
                        Button { draft = ParticipantDraft(participant: participant) } label: {
                            participantLabel(participant)
                        }
                        .accessibilityIdentifier("editParticipant_\(participant.id)")
                    } else {
                        participantLabel(participant)
                    }
                }
            }
        }
    }

    private func participantLabel(_ participant: ClubParticipant) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(participant.displayName).font(.headline).foregroundStyle(.primary)
            if let label = participant.label, !label.isEmpty {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(participant.accountID == nil ? "계정 미연결" : "회원 계정 연결됨")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ParticipantDraft: Identifiable {
    let id = UUID()
    let participantID: UUID?
    let wasActive: Bool
    var name: String
    var label: String
    var isActive: Bool

    init(participant: ClubParticipant?) {
        participantID = participant?.id
        wasActive = participant?.isActive ?? true
        name = participant?.displayName ?? ""
        label = participant?.label ?? ""
        isActive = participant?.isActive ?? true
    }
}

@MainActor
private struct ParticipantEditorView: View {
    @ObservedObject var store: ClubRosterStore
    let clubID: UUID
    @State var draft: ParticipantDraft
    @State private var submissionID: UUID?
    @State private var confirmsDeactivation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("참가자 정보") {
                    TextField("이름 (1~40자)", text: $draft.name)
                        .accessibilityIdentifier("participantNameField")
                    TextField("보조 라벨 (선택)", text: $draft.label)
                        .accessibilityIdentifier("participantLabelField")
                }
                if draft.participantID != nil {
                    Section {
                        Toggle("활동 참가자", isOn: $draft.isActive)
                            .accessibilityIdentifier("participantActiveToggle")
                    } footer: {
                        Text("비활성화해도 기존 경기 기록은 삭제되지 않습니다. 다시 활성화할 수 있습니다.")
                    }
                }
                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(.red).font(.callout) }
                }
                Section {
                    Button {
                        if draft.wasActive && !draft.isActive {
                            confirmsDeactivation = true
                        } else {
                            submissionID = UUID()
                        }
                    } label: {
                        HStack {
                            if store.isBusy { ProgressView() }
                            Text(store.isBusy ? "저장 확인 중…" : "저장")
                        }
                    }
                    .disabled((try? SaveParticipantCommand(clubID: clubID, participantID: draft.participantID,
                                                           displayName: draft.name, label: draft.label, isActive: draft.isActive)) == nil)
                    .accessibilityIdentifier("saveParticipantButton")
                } footer: {
                    Text("이름만으로 회원 계정을 자동 연결하지 않습니다. 계정 연결과 가입 승인은 별도 기능입니다.")
                }
            }
            .disabled(store.isBusy)
            .navigationTitle(draft.participantID == nil ? "참가자 추가" : "참가자 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.disabled(store.isBusy)
                }
            }
            .confirmationDialog("이 참가자를 비활성화할까요? 기존 기록은 보존됩니다.", isPresented: $confirmsDeactivation, titleVisibility: .visible) {
                Button("비활성화", role: .destructive) { submissionID = UUID() }
                Button("취소", role: .cancel) { }
            }
        }
        .interactiveDismissDisabled(store.isBusy)
        .task(id: submissionID) {
            guard submissionID != nil else { return }
            if await store.save(participantID: draft.participantID, displayName: draft.name, label: draft.label, isActive: draft.isActive) {
                dismiss()
            }
        }
    }
}
