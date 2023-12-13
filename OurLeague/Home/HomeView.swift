//
//  ContentView.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
//

import SwiftUI

struct HomeView: View {
    private var addGameButton: some View {
        HStack {
            Spacer()
            Button(action: {}, label: {
                Text("게임 시작")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(30)
            })
            .frame(width: 100, height: 60, alignment: .center)
            Spacer()
                .frame(width: 30)
        }
    }

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                addGameButton
                
                Spacer()
                    .frame(height: 30)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    Image(systemName: "ellipsis")
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.black)
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
