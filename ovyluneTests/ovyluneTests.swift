//
//  ovyluneTests.swift
//  ovyluneTests
//
//  Created by Bailey Thompson on 2026-07-11.
//

import Foundation
import Testing
@testable import ovylune

struct ovyluneTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func averageCycleLengthUsesGapsBetweenPeriodStarts() {
        let entries = [
            PeriodEntry(startDate: date(2026, 1, 1)),
            PeriodEntry(startDate: date(2026, 1, 30)),
            PeriodEntry(startDate: date(2026, 2, 26))
        ]

        #expect(CycleInsights.averageCycleLength(from: entries, calendar: calendar) == 28)
    }

    @Test func averagePeriodLengthCountsInclusiveStartAndEndDates() {
        let entries = [
            PeriodEntry(startDate: date(2026, 1, 1), endDate: date(2026, 1, 5)),
            PeriodEntry(startDate: date(2026, 1, 30), endDate: date(2026, 2, 2))
        ]

        #expect(CycleInsights.averagePeriodLength(from: entries, calendar: calendar) == 5)
    }

    @Test func summaryPredictsNextPeriodFromLastLoggedStart() {
        let entries = [
            PeriodEntry(startDate: date(2026, 1, 1)),
            PeriodEntry(startDate: date(2026, 1, 29))
        ]

        let summary = CycleInsights.summary(for: entries, calendar: calendar)

        #expect(summary.averageCycleLength == 28)
        #expect(summary.nextPeriodStart == date(2026, 2, 26))
    }

    @Test func summaryUsesFallbackCycleLengthForOneEntry() {
        let entries = [PeriodEntry(startDate: date(2026, 3, 10))]
        let summary = CycleInsights.summary(for: entries, calendar: calendar)

        #expect(summary.averageCycleLength == nil)
        #expect(summary.nextPeriodStart == date(2026, 4, 7))
    }

    @Test func detectsInclusiveAndOngoingOverlaps() {
        let entries = [
            PeriodEntry(startDate: date(2026, 1, 10), endDate: date(2026, 1, 14)),
            PeriodEntry(startDate: date(2026, 2, 1))
        ]

        #expect(PeriodEntry.overlapsExisting(startDate: date(2026, 1, 14), endDate: date(2026, 1, 18), in: entries, calendar: calendar))
        #expect(!PeriodEntry.overlapsExisting(startDate: date(2026, 1, 15), endDate: date(2026, 1, 31), in: entries, calendar: calendar))
        #expect(PeriodEntry.overlapsExisting(startDate: date(2026, 2, 10), endDate: date(2026, 2, 12), in: entries, calendar: calendar))
        #expect(PeriodEntry.overlapsExisting(startDate: date(2026, 1, 15), endDate: nil, in: entries, calendar: calendar))
    }

    @Test func overlapCheckCanExcludeEditedEntry() {
        let entry = PeriodEntry(startDate: date(2026, 1, 10), endDate: date(2026, 1, 14))

        #expect(!PeriodEntry.overlapsExisting(startDate: entry.startDate, endDate: entry.endDate, in: [entry], excluding: entry, calendar: calendar))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day).date!
    }
}
