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
            OvulationEntry.self,
            IntimacyEntry.self,
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

#if DEBUG
@MainActor
enum TestDataSeeder {
    private struct PeriodRange: Decodable {
        let start: String
        let end: String
    }

    static func seedPeriodsIfNeeded(in modelContext: ModelContext) {
        guard let fileURL = Bundle.main.url(forResource: "TestPeriodData", withExtension: "json"),
              let data = try? Data(contentsOf: fileURL),
              let periodRanges = try? JSONDecoder().decode([PeriodRange].self, from: data)
        else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        guard let existingEntries = try? modelContext.fetch(FetchDescriptor<PeriodEntry>()) else { return }
        let existingStartDates = Set(existingEntries.map { calendar.startOfDay(for: $0.startDate) })

        for range in periodRanges {
            guard let startDate = dateFormatter.date(from: range.start),
                  let endDate = dateFormatter.date(from: range.end),
                  !existingStartDates.contains(calendar.startOfDay(for: startDate))
            else { continue }

            modelContext.insert(PeriodEntry(startDate: startDate, endDate: endDate))
        }

        try? modelContext.save()
    }
}
#endif
