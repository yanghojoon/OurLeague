//
//  OurLeagueApp.swift
//  OurLeague
//
//  Created by 양호준 on 2023/12/12.
//

import SwiftUI
import SwiftData

@main
struct OurLeagueApp: App {
    @State private var needToShowStoreError = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            League.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(sharedModelContainer)
    }
}
