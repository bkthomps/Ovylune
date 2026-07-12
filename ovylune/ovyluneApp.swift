//
//  ovyluneApp.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import SwiftUI
import SwiftData

@main
struct ovyluneApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PeriodEntry.self,
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
        }
        .modelContainer(sharedModelContainer)
    }
}
