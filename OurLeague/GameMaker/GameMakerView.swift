//
//  GameMakerView.swift
//  OurLeague
//
//  Created by 양호준 on 12/29/25.
//

import SwiftUI

struct GameMakerView: View {
    @State private var courtCount: Int = 2
    
    var body: some View {
        ZStack {
            backgroundView()
                .ignoresSafeArea()
        }
    }
}

extension GameMakerView {
    private func backgroundView() -> some View {
        GeometryReader { proxy in
            let topPadding = proxy.safeAreaInsets.top // 상단 Safe Area 높이 (노치 높이)
            VStack(spacing: .zero) {
                titleView(topPadding: topPadding + 40)
                    .frame(height: topPadding + 200)
                Rectangle()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(LinearGradient(
                        colors: [
                            Color(red: 200 / 255, green: 230 / 255, blue: 220 / 255),
                            Color(red: 255 / 255, green: 255 / 255, blue: 255 / 255),
                            Color(red: 200 / 255, green: 230 / 255, blue: 220 / 255),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing)
                    )
            }
        }
    }
    private func titleView(topPadding: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255),
                    Color(red: 20 / 255, green: 140 / 255, blue: 160 / 255)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack {
                Image(systemName: "trophy")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white)
                    .frame(width: 50, height: 50)
                    .background(Color(red: 30 / 255, green: 200 / 255, blue: 150 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("테니스 경기 생성")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("오늘의 테니스 경기를 위한 정보를 입력해주세요!")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)
            }
            .padding(.top, topPadding)
        }
    }
    private func courtCountView() -> some View {
        ZStack {
            Color.white
            VStack {
                Text("게임을 진행할 코트 수")
                Spacer()
                    .frame(height: 20)
                HStack {
                    Button {
                        if courtCount >= 2 {
                            courtCount -= 1
                        }
                    } label: {
                        ZStack {
                            Color.white
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                                .overlay {
                                    Circle()
                                        .stroke(Color.black, lineWidth: 1)
                                }
                            Text("-")
                                .foregroundStyle(Color.black)
                        }
                    }
                    .padding(.horizontal, 20)
                    Text("\(courtCount)")
                        .font(.title)
                        .padding(.horizontal, 8)
                    Button {
                        courtCount += 1
                    } label: {
                        ZStack {
                            Color.white
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                                .overlay {
                                    Circle()
                                        .stroke(Color.black, lineWidth: 1)
                                }
                            Text("+")
                                .foregroundStyle(Color.black)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

#Preview {
    GameMakerView()
}
