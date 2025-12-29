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
struct OurLeagueApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            NavigationStack {
//                InformationInputView()
                SplashView()
            }
        }
    }
}
