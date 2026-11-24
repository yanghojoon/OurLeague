//
//  MembershipViews.swift
//  OurLeague
//
//  Created by 양호준 on 2026/11/24.
//

import SwiftUI

@MainActor
struct MembershipRequestView: View {
    @StateObject private var store: MembershipRequestStore
    @State private var token = ""
    @State private var reloadID = UUID()
    @State private var submissionID: UUID?
    @Environment(\.dismiss) private var dismiss
    private let accountID: UUID

    init(accountID: UUID) {
        self.accountID = accountID
        _store = StateObject(wrappedValue: MembershipRequestStore(accountID: accountID) {
            SupabaseMembershipService(client: try SupabaseEnvironment.client())
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(accountID.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    ShareLink("계정 ID 공유", item: accountID.uuidString)
                } header: {
                    Text("내 계정 ID")
                } footer: {
                    Text("운영자가 본인을 확인할 수 있도록 계정 ID를 알려 주세요. 가입 승인 전에는 동호회 내부 정보를 볼 수 없습니다.")
                }
                if store.state == .loaded {
                    Section {
                        SecureField("64자리 초대 코드", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("membershipTokenField")
                        Button(store.isBusy ? "신청 확인 중…" : "가입 신청") { submissionID = UUID() }
                            .disabled((try? MembershipCommand.request(token: token)) == nil)
                            .accessibilityIdentifier("requestMembershipButton")
                    } header: {
                        Text("회원 가입 초대")
                    } footer: {
                        Text("운영자가 공유한 회원 초대 코드만 입력하세요. 모임 게스트 초대와는 다릅니다.")
                    }
                    let pending = store.memberships.filter { $0.status == .pending }
                    Section("승인 대기 · \(pending.count)건") {
                        if pending.isEmpty {
                            Text("승인 대기 중인 신청이 없습니다.").foregroundStyle(.secondary)
                        }
                        ForEach(pending) { membership in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("운영자 승인 대기")
                                Text("동호회 ID: \(membership.clubID.uuidString)")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if store.state == .loading {
                    ProgressView("가입 상태 확인 중…")
                }
                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if let message = store.successMessage {
                    Section { Text(message).foregroundStyle(.green) }
                }
                Button("가입 상태 새로고침") { reloadID = UUID() }
            }
            .disabled(store.isBusy)
            .navigationTitle("동호회 가입")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.disabled(store.isBusy)
                }
            }
        }
        .privacySensitive()
        .interactiveDismissDisabled(store.isBusy)
        .task(id: reloadID) { await store.load() }
        .task(id: submissionID) {
            guard submissionID != nil else { return }
            if await store.request(token: token) { token = "" }
        }
    }
}

@MainActor
struct MembershipManagementView: View {
    @StateObject private var store: MembershipManagementStore
    @State private var reloadID = UUID()
    @State private var actionID: UUID?
    @State private var action: ManagementAction?
    @State private var selectedAction: ManagementAction?
    @State private var showsConfirmation = false

    init(membership: ClubMembership) {
        _store = StateObject(wrappedValue: MembershipManagementStore(membership: membership) {
            SupabaseMembershipService(client: try SupabaseEnvironment.client())
        })
    }

    var body: some View {
        List {
            if store.canManage {
                invitationSection
                if store.state == .loaded {
                    pendingSection
                    approvedSection
                } else if store.state == .loading {
                    ProgressView("회원 정보 확인 중…")
                }
                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if let message = store.successMessage {
                    Section { Text(message).foregroundStyle(.green) }
                }
                Button("회원 정보 새로고침") { reloadID = UUID() }
            } else {
                ContentUnavailableView("운영자만 관리할 수 있어요", systemImage: "lock")
            }
        }
        .disabled(store.isBusy)
        .navigationTitle("회원 초대·승인")
        .navigationBarTitleDisplayMode(.inline)
        .privacySensitive()
        .task(id: reloadID) { await store.load() }
        .task(id: actionID) {
            guard actionID != nil, let action else { return }
            switch action {
            case .issue: await store.issueInvitation()
            case .revoke: _ = await store.revokeInvitation()
            case .approve(let membershipID): _ = await store.approve(membershipID: membershipID)
            case .link(let accountID, let participantID): _ = await store.link(accountID: accountID, participantID: participantID)
            }
        }
        .confirmationDialog("회원 관리 확인", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("확인") {
                action = selectedAction
                actionID = UUID()
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var invitationSection: some View {
        Section {
            Button("회원 초대 코드 발급·재발급") { confirm(.issue) }
                .disabled(store.state != .loaded)
                .accessibilityIdentifier("issueMembershipInvitationButton")
            if let invitation = store.invitation {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if invitation.isUsable(at: context.date) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(invitation.token).font(.caption.monospaced()).textSelection(.enabled)
                            if let expiration = invitation.expirationDate {
                                Text("만료: \(expiration.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ShareLink("초대 코드 공유", item: invitation.token)
                        }
                    } else {
                        Text("만료된 초대 코드입니다. 새로 발급하세요.").foregroundStyle(.secondary)
                    }
                }
            }
            if store.invitation != nil || store.revokingInvitationID != nil {
                Button(store.revokingInvitationID == nil ? "초대 코드 폐기" : "초대 폐기 재시도", role: .destructive) {
                    confirm(.revoke)
                }
            }
        } header: {
            Text("회원 초대 · 24시간")
        } footer: {
            Text("재발급하면 이전 회원 초대 코드는 즉시 폐기됩니다. 코드는 이 화면에서만 확인할 수 있으며 앱에 저장하지 않습니다. 받은 사람은 로그인 후 ‘동호회 가입’에 입력합니다.")
        }
    }

    private var pendingSection: some View {
        let pending = store.memberships.filter { $0.status == .pending && $0.role == .member }
        return Section("승인 대기 · \(pending.count)명") {
            if pending.isEmpty { Text("승인 대기 중인 회원이 없습니다.").foregroundStyle(.secondary) }
            ForEach(pending) { member in
                VStack(alignment: .leading, spacing: 8) {
                    accountLabel(member)
                    Button("가입 승인") { confirm(.approve(member.id)) }
                        .accessibilityIdentifier("approveMembership_\(member.id)")
                }
            }
        }
    }

    private var approvedSection: some View {
        Section {
            ForEach(store.memberships.filter { $0.status == .approved }) { member in
                VStack(alignment: .leading, spacing: 8) {
                    accountLabel(member)
                    if let connected = store.participants.first(where: { $0.accountID == member.accountID && $0.isActive }) {
                        Text("명단 연결: \(connected.displayName)\(connected.label.map { " · \($0)" } ?? "")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        DisclosureGroup("기존 참가자에 연결") {
                            let available = store.participants.filter { $0.isActive && $0.accountID == nil }
                            if available.isEmpty {
                                Text("참가자 명단에 계정 미연결 참가자를 먼저 추가하세요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(available) { participant in
                                Button("\(participant.displayName)\(participant.label.map { " · \($0)" } ?? "")") {
                                    confirm(.link(member.accountID, participant.id))
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("승인된 소속 · 명단 연결")
        } footer: {
            Text("신청자가 알려 준 계정 ID로 본인을 확인하세요. 가입 승인과 명단 연결은 별개이며 이름만으로 연결하지 않습니다. 참가자 ID와 기존 기록은 유지됩니다.")
        }
    }

    private func accountLabel(_ member: Membership) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(member.role == .owner ? "운영자" : "회원")
            Text(member.accountID.uuidString).font(.caption.monospaced()).textSelection(.enabled)
        }
    }

    private func confirm(_ selected: ManagementAction) {
        selectedAction = selected
        showsConfirmation = true
    }

    private var confirmationMessage: String {
        switch selectedAction {
        case .issue:
            return "이전 회원 초대 코드를 폐기하고 24시간 유효한 새 코드를 발급합니다."
        case .revoke:
            return "이 초대 코드를 사용할 수 없게 합니다. 기존 가입 신청과 승인은 취소되지 않습니다."
        case .approve(let membershipID):
            let account = store.memberships.first { $0.id == membershipID }?.accountID.uuidString ?? ""
            return "계정 \(account)의 동호회 가입을 승인할까요? 동호회 내부 정보를 조회할 수 있게 됩니다."
        case .link(let accountID, let participantID):
            let name = store.participants.first { $0.id == participantID }?.displayName ?? ""
            return "계정 \(accountID.uuidString)을 참가자 ‘\(name)’ (\(participantID.uuidString))에 연결할까요? 이름이 같아도 반드시 본인을 확인하세요."
        case nil:
            return ""
        }
    }

    private enum ManagementAction {
        case issue, revoke
        case approve(UUID)
        case link(UUID, UUID)
    }
}
