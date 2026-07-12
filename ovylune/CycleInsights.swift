//
//  CycleInsights.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import Foundation

struct CycleSummary {
    let averageCycleLength: Int?
    let averagePeriodLength: Int?
    let nextPeriodStart: Date?
    let lastPeriodStart: Date?
}

enum CycleInsights {
    static let fallbackCycleLength = 28
    static let fallbackPeriodLength = 5

    static func summary(for entries: [PeriodEntry], calendar: Calendar = .current) -> CycleSummary {
        let sorted = entries.sorted { $0.startDate < $1.startDate }
        let averageCycleLength = averageCycleLength(from: sorted, calendar: calendar)
        let averagePeriodLength = averagePeriodLength(from: sorted, calendar: calendar)
        let lastStart = sorted.last?.startDate
        let nextStart = lastStart.flatMap {
            calendar.date(byAdding: .day, value: averageCycleLength ?? fallbackCycleLength, to: calendar.startOfDay(for: $0))
        }

        return CycleSummary(
            averageCycleLength: averageCycleLength,
            averagePeriodLength: averagePeriodLength,
            nextPeriodStart: nextStart,
            lastPeriodStart: lastStart
        )
    }

    static func averageCycleLength(from entries: [PeriodEntry], calendar: Calendar = .current) -> Int? {
        let sortedStarts = entries
            .map { calendar.startOfDay(for: $0.startDate) }
            .sorted()

        guard sortedStarts.count >= 2 else { return nil }

        let gaps = zip(sortedStarts, sortedStarts.dropFirst()).compactMap { previous, current in
            calendar.dateComponents([.day], from: previous, to: current).day
        }

        guard !gaps.isEmpty else { return nil }
        return Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }

    static func averagePeriodLength(from entries: [PeriodEntry], calendar: Calendar = .current) -> Int? {
        let lengths = entries.compactMap { entry -> Int? in
            guard let endDate = entry.endDate else { return nil }
            let start = calendar.startOfDay(for: entry.startDate)
            let end = calendar.startOfDay(for: endDate)
            guard end >= start else { return nil }
            return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        }

        guard !lengths.isEmpty else { return nil }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }
}

