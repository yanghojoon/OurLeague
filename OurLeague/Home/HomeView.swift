//
//  ContentView.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
//

import SwiftUI

struct HomeView: View {
    @State private var playerInfo: Player?
    @State private var needToGoClubView = false
    @State private var date = Date()

    var body: some View {
        GeometryReader { proxy in
            NavigationStack {
                ZStack {
                    Color.orange.opacity(0.3)
                        .ignoresSafeArea()
                    VStack {
                        Spacer()
                            .frame(height: 20)
                        clubInfoView(viewWidth: proxy.size.width)
                        Spacer()
                            .frame(height: 10)
                        reportView(viewWidth: proxy.size.width)
                            .frame(width: proxy.size.width - 40, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 4)
                        Spacer()
                            .frame(height: 10)
                        intendedGameView(viewWidth: proxy.size.width)
                            .frame(width: proxy.size.width - 40, height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 4)
                        Spacer()
                        addGameButton(viewWidth: proxy.size.width)
                        Spacer()
                            .frame(height: 30)
                    }
                }
                .navigationDestination(isPresented: $needToGoClubView) {
                    ClubInfoView()
                }
            }
        }
    }

    private func clubInfoView(viewWidth: CGFloat) -> some View {
        ZStack {
            Color.white
            VStack {
                Spacer()
                HStack {
                    Text("안녕하세요! ")
                        .font(.title3)
                    Text("\(playerInfo?.name ?? "이름 없음")")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.orange)
                    Text("님 😄")
                        .font(.title3)
                }
                .frame(width: viewWidth - 70, alignment: .leading)
                Spacer()
                    .frame(height: 10)
                Text("오늘도 즐테하세요 🎾")
                    .font(.subheadline)
                    .frame(width: viewWidth - 70, alignment: .leading)
                Spacer()
                    .frame(height: 20)
                HStack {
                    Text("소속 클럽: ")
                    Button {
                        needToGoClubView = true
                    } label: {
                        Text("\(playerInfo?.club.name ?? "클럽 이름 업성용")")
                            .foregroundStyle(Color.orange.opacity(0.8))
                            .underline()
                            .fontWeight(.bold)
                    }

                }
                .frame(width: viewWidth - 70, alignment: .leading)
                Spacer()
            }
        }
        .frame(width: viewWidth - 40, height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    private func reportView(viewWidth: CGFloat) -> some View {
        ZStack {
            Color.white

            VStack {
                Spacer()
                HStack {
                    Text("🥇 순위")
                        .font(.subheadline)
                    Text("\(playerInfo?.ranking ?? 0)위")
                        .font(.subheadline)
                }
                .frame(width: viewWidth - 70, alignment: .leading)
                Spacer()
                    .frame(height: 5)
                HStack {
                    Text("🏆 전적")
                        .font(.subheadline)
                    Text("\(playerInfo?.totalGameCount ?? 0)전 \(playerInfo?.winCount ?? 0)승")
                        .font(.subheadline)
                }
                .frame(width: viewWidth - 70, alignment: .leading)
                Spacer()
                    .frame(height: 5)
                HStack {
                    Text("📊 승률")
                        .font(.subheadline)
                    Text("\((playerInfo?.winCount ?? 0) / (playerInfo?.totalGameCount ?? 1))%")
                        .font(.subheadline)
                }
                .frame(width: viewWidth - 70, alignment: .leading)
                Spacer()
            }
        }
    }

    private func intendedGameView(viewWidth: CGFloat) -> some View {
        ZStack {
            Color.white

            VStack {
                Spacer()
                    .frame(height: .zero)
                Color.red
                    .frame(width: .infinity, height: 16)
                Spacer()
                    .frame(height: 20)
                HStack {
                    CalenderView(
                        month: Date(),
                        clickedDates: Set(playerInfo?.club.intendedGame.map({ $0.date }) ?? [])
                    )
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private func addGameButton(viewWidth: CGFloat) -> some View {
        Button(action: {
        // TODO: 게임 생성 화면 전환
        }, label: {
            ZStack {
                Color.green
                Text("Game Start!")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding()
            }
            .frame(width: viewWidth - 80, height: 50)
        })
        .background(Color.green)
        .cornerRadius(30)
        .shadow(radius: 4)
    }
}

#Preview {
    HomeView()
}
