//
//  MyInformationView.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/13.
//

import SwiftUI

//struct InformationInputView: View {
//    @State private var nameText = ""
//    @State private var clubText = "클럽 이름을 입력해주세요"
//    @State private var needSearchModal = false
//    
//    private let clubPlaceholder = "클럽 이름을 입력해주세요"
//    
//    var body: some View {
//        ZStack {
//            Color(.secondarySystemBackground)
//                .ignoresSafeArea()
//            VStack {
//                Spacer()
//                    .frame(height: 20)
//                Text("정보를 입력해주세요")
//                    .foregroundStyle(.black)
//                    .font(.title)
//                Spacer()
//                    .frame(height: 20)
//                nameInputView
//                Spacer()
//                    .frame(height: 30)
//                clubInputView
//                Spacer()
//            }
//        }
//    }
//}
//
//extension InformationInputView {
//    private var nameInputView: some View {
//        VStack {
//            HStack {
//                Spacer()
//                    .frame(width: 20)
//                Text("이름")
//                    .foregroundStyle(.black)
//                    .font(.headline)
//                Spacer()
//            }
//            TextField("사용할 이름을 입력해주세요", text: $nameText)
//                .padding()
//                .background(Color(uiColor: .secondarySystemBackground))
//                .textFieldStyle(.roundedBorder)
//        }
//    }
//    
//    private var clubInputView: some View {
//        VStack {
//            HStack {
//                Spacer()
//                    .frame(width: 20)
//                Text("클럽")
//                    .foregroundStyle(.black)
//                    .font(.headline)
//                Spacer()
//            }
//            HStack {
//                Spacer()
//                    .frame(width: 20)
//                Text("해당 정보를 통해 경기 정보를 불러옵니다")
//                    .foregroundStyle(.black)
//                    .font(.subheadline)
//                Spacer()
//            }
//            Spacer()
//                .frame(height: 15)
//            Button {
//                self.needSearchModal = true
//            } label: {
//                GeometryReader { geometry in
//                    HStack {
//                        Spacer()
//                            .frame(width: 18)
//                        Text("\(clubText)")
//                            .padding(8)
//                            .frame(width: abs(geometry.size.width - 36), height: 34, alignment: .leading)
//                            .background(Color.white)
//                            .clipShape(.rect(cornerRadii: .init(
//                                topLeading: 4,
//                                bottomLeading: 4,
//                                bottomTrailing: 4,
//                                topTrailing: 4
//                            )))
//                            .overlay {
//                                RoundedRectangle(cornerRadius: 4)
//                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
//                            }
//                            .foregroundStyle(clubText == clubPlaceholder ? .gray.opacity(0.5) : .black)
//                        Spacer()
//                            .frame(width: 18)
//                    }
//                }
//            }
//            .buttonStyle(.plain)
//            .sheet(isPresented: $needSearchModal) {
//                SearchClubModalView()
//            }
//        }
//    }
//}
//
//#Preview {
//    InformationInputView()
//}
