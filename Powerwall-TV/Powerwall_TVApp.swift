//
//  Powerwall_TVApp.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//

import SwiftUI
import SwiftData

@main
struct Powerwall_TVApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
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
            ContentView()
#if os(macOS)
                .frame(width: 1280, height: 720)
#endif
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .windowResizability(.contentSize)
#endif
    }
}
