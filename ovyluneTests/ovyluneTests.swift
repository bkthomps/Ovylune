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

    @Test func intimacyTracksPregnancyByDefault() {
        #expect(IntimacyEntry(date: date(2026, 7, 12)).trackPregnancy)
        #expect(!IntimacyEntry(date: date(2026, 7, 12), trackPregnancy: false).trackPregnancy)
    }

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

    @Test func averageCycleLengthFavorsRecentCyclesWithOneYearHalfLife() {
        let offsets = [0, 100] + (1...10).map { 100 + ($0 * 28) }
        let entries = offsets.map { offset in
            PeriodEntry(
                startDate: calendar.date(byAdding: .day, value: offset, to: date(2020, 1, 1))!
            )
        }

        // An unweighted mean rounds to 35; decay pulls the estimate toward the
        // ten recent 28-day cycles.
        #expect(CycleInsights.averageCycleLength(from: entries, calendar: calendar) == 33)
    }

    @Test func averagePeriodLengthFavorsRecentPeriodsWithTwoYearHalfLife() {
        let entries = [
            PeriodEntry(startDate: date(2018, 1, 1), endDate: date(2018, 1, 10)),
            PeriodEntry(startDate: date(2022, 1, 1), endDate: date(2022, 1, 4))
        ]

        // Four years makes the older 10-day period one quarter as influential.
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

    @Test func summaryAdjustsCycleLengthForOneCompletedPeriod() {
        let entries = [
            PeriodEntry(startDate: date(2026, 3, 10), endDate: date(2026, 3, 17))
        ]
        let summary = CycleInsights.summary(for: entries, calendar: calendar)

        #expect(summary.averagePeriodLength == 8)
        #expect(summary.averageCycleLength == 31)
        #expect(summary.nextPeriodStart == date(2026, 4, 10))
        #expect(summary.cycleConfidence == .low)
        #expect(summary.periodConfidence == .low)
    }

    @Test func advancesPastPredictionToNextUpcomingCycle() {
        let entries = [
            PeriodEntry(startDate: date(2026, 1, 1), endDate: date(2026, 1, 31))
        ]
        let summary = CycleInsights.summary(for: entries, calendar: calendar)

        #expect(summary.averageCycleLength == 54)
        #expect(summary.nextPeriodStart == date(2026, 2, 24))
        #expect(
            CycleInsights.nextPrediction(
                startingOn: summary.nextPeriodStart!,
                cycleLength: summary.averageCycleLength!,
                onOrAfter: date(2026, 4, 1),
                calendar: calendar
            ) == date(2026, 4, 19)
        )
        #expect(
            CycleInsights.nextPrediction(
                startingOn: summary.nextPeriodStart!,
                cycleLength: summary.averageCycleLength!,
                onOrAfter: date(2026, 6, 1),
                calendar: calendar
            ) == date(2026, 6, 12)
        )
        #expect(
            CycleInsights.nextPrediction(
                startingOn: summary.nextPeriodStart!,
                cycleLength: summary.averageCycleLength!,
                onOrAfter: date(2026, 7, 12),
                calendar: calendar
            ) == date(2026, 8, 5)
        )
    }

    @Test func predictionRoundsOnlyAfterAccumulatingFractionalCycles() {
        let start = date(2026, 1, 1)

        #expect(
            CycleInsights.nextPrediction(
                startingOn: start,
                cycleLength: 28.4,
                onOrAfter: date(2026, 2, 1),
                calendar: calendar
            ) == date(2026, 2, 27)
        )
        #expect(
            CycleInsights.nextPrediction(
                startingOn: start,
                cycleLength: 28.4,
                onOrAfter: date(2026, 2, 28),
                calendar: calendar
            ) == date(2026, 3, 27)
        )
    }

    @Test func summaryUsesConfidenceBasedOnEachEstimatesDataPoints() {
        let entries = (0..<7).map { index in
            let start = date(2026, 1, 1 + (index * 28))
            return PeriodEntry(
                startDate: start,
                endDate: index < 4 ? calendar.date(byAdding: .day, value: 4, to: start) : nil
            )
        }

        let summary = CycleInsights.summary(for: entries, calendar: calendar)

        #expect(summary.cycleConfidence == .high)
        #expect(summary.periodConfidence == .medium)
    }

    @Test func summaryUsesDefaultConfidenceWithoutUsableData() {
        let summary = CycleInsights.summary(for: [], calendar: calendar)

        #expect(summary.cycleConfidence == .defaultEstimate)
        #expect(summary.periodConfidence == .defaultEstimate)
    }

    @Test func irregularCyclesReduceConfidenceDespiteHavingManyDataPoints() {
        let offsets = [0, 20, 55, 77, 120, 146, 190]
        let entries = offsets.map { offset in
            PeriodEntry(startDate: calendar.date(byAdding: .day, value: offset, to: date(2026, 1, 1))!)
        }

        let summary = CycleInsights.summary(for: entries, calendar: calendar)

        #expect(summary.cycleConfidence == .low)
        #expect(summary.isCycleIrregular)
    }

    @Test func irregularPeriodLengthsReduceConfidenceDespiteHavingManyDataPoints() {
        let lengths = [3, 9, 4, 8, 2, 10]
        let entries = lengths.enumerated().map { index, length in
            let start = calendar.date(byAdding: .day, value: index * 28, to: date(2026, 1, 1))!
            return PeriodEntry(
                startDate: start,
                endDate: calendar.date(byAdding: .day, value: length - 1, to: start)
            )
        }

        let summary = CycleInsights.summary(for: entries, calendar: calendar)

        #expect(summary.periodConfidence == .low)
        #expect(summary.isPeriodLengthIrregular)
    }

    @Test func irregularityRequiresThreeRecentDataPoints() {
        #expect(!CycleInsights.isIrregular([20, 40], maximumRegularRange: 9))
        #expect(!CycleInsights.isIrregular([27, 28, 36], maximumRegularRange: 9))
        #expect(CycleInsights.isIrregular([27, 28, 37], maximumRegularRange: 9))
    }

    @Test func estimatedPeriodEndUsesAveragePeriodLength() {
        let entries = [
            PeriodEntry(startDate: date(2026, 1, 1), endDate: date(2026, 1, 5)),
            PeriodEntry(startDate: date(2026, 2, 1), endDate: date(2026, 2, 3))
        ]

        #expect(
            CycleInsights.estimatedPeriodEnd(
                startingOn: date(2026, 3, 10),
                entries: entries,
                calendar: calendar
            ) == date(2026, 3, 13)
        )
    }

    @Test func estimatedPeriodEndUsesFallbackWithoutCompletedPeriods() {
        #expect(
            CycleInsights.estimatedPeriodEnd(
                startingOn: date(2026, 3, 10),
                entries: [],
                calendar: calendar
            ) == date(2026, 3, 14)
        )
    }

    @Test func predictsOvulationFromLoggedOvulationIntervalWhenEnoughDataExists() {
        let ovulations = [
            OvulationEntry(startDate: date(2026, 1, 14)),
            OvulationEntry(startDate: date(2026, 2, 12)),
            OvulationEntry(startDate: date(2026, 3, 12))
        ]

        #expect(CycleInsights.averageOvulationInterval(from: ovulations, calendar: calendar) == 29)
        #expect(
            CycleInsights.nextOvulationDate(
                from: ovulations,
                nextPeriodStart: date(2026, 4, 10),
                calendar: calendar
            ) == date(2026, 4, 10)
        )
    }

    @Test func predictsOvulationFourteenDaysBeforeNextPeriodWithoutEnoughOvulationData() {
        let ovulations = [OvulationEntry(startDate: date(2026, 1, 14))]

        #expect(
            CycleInsights.nextOvulationDate(
                from: ovulations,
                nextPeriodStart: date(2026, 3, 20),
                calendar: calendar
            ) == date(2026, 3, 6)
        )
    }

    @Test func loggedOvulationMovesNextPeriodPredictionToEndOfLutealPhase() {
        let periods = [
            PeriodEntry(startDate: date(2026, 1, 1)),
            PeriodEntry(startDate: date(2026, 1, 29))
        ]
        let ovulations = [OvulationEntry(startDate: date(2026, 2, 15))]

        #expect(
            CycleInsights.nextPeriodStart(
                from: periods,
                ovulationEntries: ovulations,
                calendar: calendar
            ) == date(2026, 3, 1)
        )
    }

    @Test func latestLoggedOvulationIsUsedWhenCycleHasMoreThanOne() {
        let periods = [PeriodEntry(startDate: date(2026, 1, 29))]
        let ovulations = [
            OvulationEntry(startDate: date(2026, 2, 10)),
            OvulationEntry(startDate: date(2026, 2, 12), endDate: date(2026, 2, 13))
        ]

        #expect(
            CycleInsights.nextPeriodStart(
                from: periods,
                ovulationEntries: ovulations,
                calendar: calendar
            ) == date(2026, 2, 27)
        )
    }

    @Test func learnsLutealPhaseLengthFromCompletedCycles() {
        let periods = [
            PeriodEntry(startDate: date(2026, 1, 1)),
            PeriodEntry(startDate: date(2026, 1, 31)),
            PeriodEntry(startDate: date(2026, 3, 2))
        ]
        let ovulations = [
            OvulationEntry(startDate: date(2026, 1, 18)),
            OvulationEntry(startDate: date(2026, 2, 16))
        ]

        #expect(
            CycleInsights.averageLutealPhaseLength(
                periodEntries: periods,
                ovulationEntries: ovulations,
                calendar: calendar
            ) == 14
        )
    }

    @Test func onlyLatestOvulationInMonthIsPreferred() {
        let earlier = OvulationEntry(startDate: date(2026, 2, 10))
        let later = OvulationEntry(startDate: date(2026, 2, 14))

        #expect(
            CycleInsights.preferredOvulationEntries(
                from: [earlier, later],
                calendar: calendar
            ).map(\.startDate) == [later.startDate]
        )
        #expect(CycleInsights.isSupersededOvulation(earlier, in: [earlier, later], calendar: calendar))
        #expect(!CycleInsights.isSupersededOvulation(later, in: [earlier, later], calendar: calendar))
    }

    @Test func historicalLutealPredictionDoesNotUseFutureCycles() {
        let periods = [
            PeriodEntry(startDate: date(2026, 1, 1)),
            PeriodEntry(startDate: date(2026, 1, 31)),
            PeriodEntry(startDate: date(2026, 3, 2))
        ]
        let ovulations = [
            OvulationEntry(startDate: date(2026, 1, 18)), // 13 days
            OvulationEntry(startDate: date(2026, 2, 10))  // 20 days, future at cutoff
        ]

        #expect(
            CycleInsights.averageLutealPhaseLength(
                periodEntries: periods,
                ovulationEntries: ovulations,
                before: date(2026, 1, 31),
                calendar: calendar
            ) == 13
        )
        #expect(
            CycleInsights.preciseAverageLutealPhaseLength(
                periodEntries: periods,
                ovulationEntries: ovulations,
                before: date(2026, 1, 31),
                calendar: calendar
            ) == 13.0
        )
    }

    @Test func learnsInclusiveOvulationLengthFromPastRanges() {
        let entries = [
            OvulationEntry(startDate: date(2026, 1, 10), endDate: date(2026, 1, 12)),
            OvulationEntry(startDate: date(2026, 2, 10), endDate: date(2026, 2, 13)),
            OvulationEntry(startDate: date(2026, 4, 10), endDate: date(2026, 4, 20))
        ]

        #expect(
            CycleInsights.averageOvulationLength(
                from: entries,
                before: date(2026, 3, 1),
                calendar: calendar
            ) == 4
        )
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

    @Test func periodRangesOverlapOvulationDatesInclusively() {
        let ovulations = [
            OvulationEntry(startDate: date(2026, 1, 14)),
            OvulationEntry(startDate: date(2026, 2, 5), endDate: date(2026, 2, 7))
        ]

        #expect(PeriodEntry.overlapsExisting(startDate: date(2026, 1, 10), endDate: date(2026, 1, 14), in: ovulations, calendar: calendar))
        #expect(!PeriodEntry.overlapsExisting(startDate: date(2026, 1, 15), endDate: date(2026, 2, 4), in: ovulations, calendar: calendar))
        #expect(PeriodEntry.overlapsExisting(startDate: date(2026, 2, 6), endDate: nil, in: ovulations, calendar: calendar))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day).date!
    }
}
