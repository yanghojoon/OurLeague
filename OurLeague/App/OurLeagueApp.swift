//
//  OurLeagueApp.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
//

import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
  ) -> Bool {
      return true
  }
}

@main
@MainActor
struct OurLeagueApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authStore = AuthStore {
        SupabaseAuthService(client: try SupabaseEnvironment.client())
    }

    var body: some Scene {
        WindowGroup {
            SplashView(authStore: authStore)
        }
    }
}
