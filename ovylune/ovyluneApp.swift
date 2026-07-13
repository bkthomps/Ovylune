//
//  ovyluneApp.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import SwiftUI
import SwiftData
import Foundation

private enum LocalDataStore {
    private static let storeFileName = "default.store"

    static func makeContainer(for schema: Schema) throws -> ModelContainer {
        let applicationSupportDirectory = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(applicationSupportDirectory)

        let configuration = ModelConfiguration(
            schema: schema,
            url: applicationSupportDirectory.appending(path: storeFileName)
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        if try context.fetchCount(FetchDescriptor<AppSettings>()) == 0 {
            context.insert(AppSettings())
            try context.save()
        }

        // The directory exclusion covers sidecars created later. Mark files that
        // already exist as well so the backup policy is explicit on each one.
        for suffix in ["", "-wal", "-shm"] {
            let fileURL = applicationSupportDirectory.appending(path: storeFileName + suffix)
            if FileManager.default.fileExists(atPath: fileURL.path()) {
                try excludeFromBackup(fileURL)
            }
        }

        return container
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
    }
}

@main
struct ovyluneApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AppSettings.self,
            PeriodEntry.self,
            OvulationEntry.self,
            IntimacyEntry.self,
        ])
        do {
            return try LocalDataStore.makeContainer(for: schema)
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
