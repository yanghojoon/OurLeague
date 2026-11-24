//
//  ClubInfoView.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import SwiftUI

struct ClubInfoView: View {
    let membership: ClubMembership
    let showClubList: () -> Void

    var body: some View {
        List {
            Section {
                Text(membership.club.name).font(.title2.bold())
                if !membership.club.description.isEmpty {
                    Text(membership.club.description)
                }
                LabeledContent("내 역할", value: membership.membership.role == .owner ? "운영자" : "회원")
                LabeledContent("동호회 상태", value: statusText)
            }
            Section {
                NavigationLink {
                    ClubRosterView(membership: membership)
                        .id(membership.id)
                } label: {
                    Label("참가자 명단", systemImage: "person.3")
                }
                .accessibilityIdentifier("clubRosterLink")
                if membership.canManage {
                    NavigationLink {
                        MembershipManagementView(membership: membership)
                            .id(membership.id)
                    } label: {
                        Label("회원 초대·가입 승인", systemImage: "person.badge.key")
                    }
                    .accessibilityIdentifier("membershipManagementLink")
                }
                Label("모임 연결 준비 중", systemImage: "calendar")
                    .foregroundStyle(.secondary)
                Text("아직 이 동호회의 모임·경기 기록 기능은 연결되지 않았습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("다른 동호회 선택", action: showClubList)
                    .accessibilityIdentifier("switchClubButton")
            }
        }
        .navigationTitle("동호회")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        switch membership.club.status {
        case .active: return "활동 중"
        case .closed: return "종료됨"
        case .needsOwner: return "운영자 지정 필요"
        }
    }
}
