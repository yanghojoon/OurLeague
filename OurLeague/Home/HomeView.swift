//
//  ContentView.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
//

import SwiftUI

struct HomeView: View {
    @State private var playerInfo: Player? = Player(
        name: "호준",
        club: Club(
            id: UUID().uuidString,
            name: "온더코트",
            member: [],
            gameHistory: [],
            intendedGame: [
                GameByDay(
                    date: Date(),
                    startTime: Date(),
                    endTime: Date(),
                    games: [],
                    participants: [],
                    location: "북중"
                ),
                GameByDay(
                    date: Date().addingTimeInterval(123401),
                    startTime: Date(),
                    endTime: Date(),
                    games: [],
                    participants: [],
                    location: "신봉고가"
                ),
                GameByDay(
                    date: Date().addingTimeInterval(223401),
                    startTime: Date(),
                    endTime: Date(),
                    games: [],
                    participants: [],
                    location: "긴긴긴긴 테니스 장 이름이 길다 길어"
                ),
                GameByDay(
                    date: Date().addingTimeInterval(523401),
                    startTime: Date(),
                    endTime: Date(),
                    games: [],
                    participants: [],
                    location: "긴긴긴"
                ),
            ],
            locations: ["북중", "신봉고가"]
        ),
        totalGameCount: 99,
        winCount: 72,
        ranking: 1
    )
    @State private var needToGoClubView = false
    @State private var date = Date()

    var body: some View {
        GeometryReader { proxy in
            NavigationStack {
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.orange]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
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
                            .frame(width: proxy.size.width - 40, height: 220)
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
        let totalGameCount = playerInfo?.totalGameCount ?? 1
        let winCount = playerInfo?.winCount ?? 0
        return ZStack {
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
                    Text("\(Int(Double(winCount) / Double(totalGameCount) * 100))%")
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
//                Spacer()
//                    .frame(height: .zero)
//                Color.red
//                    .frame(width: .infinity, height: 16)
//                Spacer()
                HStack {
                    Spacer()
                        .frame(width: 10)
                    CalendarView(
                        month: Date(),
                        clickedDates: Set(playerInfo?.club.intendedGame.map({ $0.date }) ?? [])
                    )
                    .frame(width: viewWidth - 180, height: 200)
                    Spacer()

                    VStack {
                        Spacer().frame(height: 20)
                        Text("예정 경기")
                            .font(.caption)
                        scheduleListView
//                            .frame(
//                                height: CGFloat(playerInfo?.club.intendedGame.count ?? .zero)
//                            )
                        if playerInfo?.club.intendedGame.count ?? 0 > 3 {
                            Text("+ \((playerInfo?.club.intendedGame.count ?? 0) - 3)")
                                .font(.footnote)
                        }
                        Spacer()
                    }
                    Spacer()
                        .frame(width: 10)
                }
//                Spacer()
            }
        }
    }

    private var scheduleListView: some View {
        let gridItems = playerInfo?.club.intendedGame
            .map({ _ in GridItem(.fixed(40), spacing: 5) })
            .prefix(3) ?? []
        return LazyHGrid(
            rows: Array(gridItems),
            spacing: 5
        ) {
            ForEach(Array(playerInfo?.club.intendedGame.prefix(upTo: 3) ?? []), id: \.self) { intendedGame  in
                scheduleView(intendedGame: intendedGame)
            }
        }
    }

    private func scheduleView(intendedGame: GameByDay) -> some View {
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "M월 d일 HH시"
            return formatter
        }()

        return RoundedRectangle(cornerRadius: 8)
            .frame(width: 90, height: 40)
            .foregroundStyle(Color.green)
            .overlay {
                VStack {
                    Text(intendedGame.location)
                        .font(.caption)
                    Text(intendedGame.startTime, formatter: dateFormatter)
                        .font(.caption2)
                }
                .foregroundStyle(Color.white)
            }
    }

    private func addGameButton(viewWidth: CGFloat) -> some View {
        Button(action: {
        // TODO: 게임 생성 화면 전환
        }, label: {
            ZStack {
                Color.white
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
