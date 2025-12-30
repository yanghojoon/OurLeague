//
//  GameMakerView.swift
//  OurLeague
//
//  Created by 양호준 on 12/29/25.
//

import SwiftUI

struct GameMakerView: View {
    @State private var courtCount: Int = 1
    @State private var gameCount: Int = 1
    @State private var participants: [String] = []
    @State private var playerName: String = ""
    @State private var isGameStarted = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            backgroundView()
                .ignoresSafeArea()
        }
        .onTapGesture {
            isFocused = false
        }
    }
}

// MARK: - SubViews
extension GameMakerView {
    private func backgroundView() -> some View {
        GeometryReader { proxy in
            let topPadding = proxy.safeAreaInsets.top // 상단 Safe Area 높이 (노치 높이)
            VStack(spacing: .zero) {
                titleView(topPadding: topPadding + 40)
                    .frame(height: topPadding + 200)
                contentView()
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
    
    private func contentView() -> some View {
        ZStack {
            // 배경 그라데이션
            LinearGradient(
                colors: [
                    Color(red: 200 / 255, green: 230 / 255, blue: 220 / 255),
                    Color.white,
                    Color(red: 200 / 255, green: 230 / 255, blue: 220 / 255),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            
            ScrollViewReader { scrollProxy in
                ScrollView {
                    participantInputView()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .gray.opacity(0.4), radius: 5, x: 4, y: 4)
                        .padding(.horizontal)
                        .padding(.top, 20)
                    
                    courtCountView()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .gray.opacity(0.4), radius: 5, x: 4, y: 4)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    gameCountView()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .gray.opacity(0.4), radius: 5, x: 4, y: 4)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .padding(.bottom)
            }
            
            VStack {
                Spacer()
                floatingBottomBar()
            }
            .ignoresSafeArea(.keyboard)
            
        }
    }
    
    private func floatingBottomBar() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: {
                    courtCount = 1
                    gameCount = 1
                    participants = []
                }) {
                    Text("초기화")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray, lineWidth: 1)
                        }
                }
                
                Button {
                    isGameStarted = true
                } label: {
                    Text("게임 생성")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255))
                        .cornerRadius(8)
                }
                
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(
            Rectangle()
                .foregroundStyle(Color.white)
                .overlay {
                    Rectangle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                }
        )
    }
    
    private func courtCountView() -> some View {
        ZStack {
            Color.white
            VStack {
                HStack {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 12))
                        .frame(width: 25, height: 25)
                        .foregroundStyle(Color(red: 20 / 255, green: 140 / 255, blue: 30 / 255))
                        .background(Color.green.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.leading, 20)
                        .padding(.top, 16)
                    Text("동시 진행 코트 수")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.top, 16)
                    Spacer()
                }
                
                Spacer()
                    .frame(height: 20)
                Stepper {
                    Text("\(courtCount)")
                        .font(.headline)
                } onIncrement: {
                    courtCount += 1
                } onDecrement: {
                    if courtCount >= 2 {
                        courtCount -= 1
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
    
    private func gameCountView() -> some View {
        ZStack {
            Color.white
            VStack {
                HStack {
                    Image(systemName: "tennis.racket")
                        .font(.system(size: 12))
                        .frame(width: 25, height: 25)
                        .foregroundStyle(Color(red: 20 / 255, green: 140 / 255, blue: 30 / 255))
                        .background(Color.green.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.leading, 20)
                        .padding(.top, 16)
                    Text("게임 수")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.top, 16)
                    Spacer()
                }
                
                Spacer()
                    .frame(height: 20)
                Stepper {
                    Text("\(gameCount)")
                        .font(.headline)
                } onIncrement: {
                    gameCount += 1
                } onDecrement: {
                    if courtCount >= 2 {
                        gameCount -= 1
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
    
    private func participantInputView() -> some View {
        ZStack {
            Color.white
            VStack(alignment: .leading) { // 정렬 추가
                HStack {
                    Image(systemName: "person")
                        .font(.system(size: 12))
                        .frame(width: 25, height: 25)
                        .foregroundStyle(Color(red: 20 / 255, green: 140 / 255, blue: 30 / 255))
                        .background(Color.green.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    Text("참가자 (\(participants.count)명)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.top, 16)
                
                if !participants.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(participants, id: \.self) { player in
                                HStack {
                                    Text(player)
                                        .font(.caption)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8))
                                        .frame(width: 10, height: 10)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                                .onTapGesture {
                                    if let index = participants.firstIndex(of: player) {
                                        participants.remove(at: index)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 5)
                }
                
                HStack {
                    TextField("이름 입력", text: $playerName)
                        .font(.system(size: 14))
                        .focused($isFocused)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !playerName.isEmpty {
                                participants.append(playerName)
                                playerName = ""
                                isFocused = true
                            }
                        }
                    
                    Button {
                        participants.append(playerName)
                        playerName = ""
                    } label: {
                        Text("추가")
                            .frame(width: 40, height: 28)
                            .foregroundStyle(Color.white)
                            .font(.system(size: 14))
                            .background(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

#Preview {
    GameMakerView()
}
