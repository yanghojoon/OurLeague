//
//  SplashView.swift
//  OurLeague
//
//  Created by 양호준 on 2/6/25.
//

import SwiftUI

struct SplashView: View {
    @State private var navigateToNextPage = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.green, Color.yellow]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            Image(systemName: "tennis.racket.circle")
                .resizable()
                .frame(width: 100, height: 100)
            if navigateToNextPage {
                HomeView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
                navigateToNextPage = true
            }
        }
    }
}

#Preview {
    SplashView()
}
