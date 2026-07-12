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
    let lastPeriodEnd: Date?
}

enum CycleInsights {
    static let fallbackCycleLength = 28
    static let fallbackPeriodLength = 5
    static let fallbackLutealPhaseLength = 14
    static let fertileDaysBeforeOvulation = 5
    static let fertileDaysAfterOvulation = 1

    static func summary(for entries: [PeriodEntry], calendar: Calendar = .current) -> CycleSummary {
        let sorted = entries.sorted { $0.startDate < $1.startDate }
        let averageCycleLength = averageCycleLength(from: sorted, calendar: calendar)
        let averagePeriodLength = averagePeriodLength(from: sorted, calendar: calendar)
        let lastEntry = sorted.last
        let lastStart = lastEntry?.startDate
        let nextStart = lastStart.flatMap {
            calendar.date(byAdding: .day, value: averageCycleLength ?? fallbackCycleLength, to: calendar.startOfDay(for: $0))
        }

        return CycleSummary(
            averageCycleLength: averageCycleLength,
            averagePeriodLength: averagePeriodLength,
            nextPeriodStart: nextStart,
            lastPeriodStart: lastStart,
            lastPeriodEnd: lastEntry?.endDate
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

    static func averageOvulationInterval(
        from entries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> Int? {
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

    static func nextOvulationDate(
        from ovulationEntries: [OvulationEntry],
        nextPeriodStart: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        if let interval = averageOvulationInterval(from: ovulationEntries, calendar: calendar),
           let latest = ovulationEntries.map(\.startDate).max() {
            return calendar.date(
                byAdding: .day,
                value: interval,
                to: calendar.startOfDay(for: latest)
            )
        }

        guard let nextPeriodStart else { return nil }
        return calendar.date(
            byAdding: .day,
            value: -fallbackLutealPhaseLength,
            to: calendar.startOfDay(for: nextPeriodStart)
        )
    }

    static func nextPeriodStart(
        from periodEntries: [PeriodEntry],
        ovulationEntries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> Date? {
        let summary = summary(for: periodEntries, calendar: calendar)
        guard let lastPeriodStart = summary.lastPeriodStart else { return nil }

        let normalizedLastPeriodStart = calendar.startOfDay(for: lastPeriodStart)
        let latestOvulationEnd = preferredOvulationEntries(from: ovulationEntries, calendar: calendar).compactMap { entry -> Date? in
            let start = calendar.startOfDay(for: entry.startDate)
            guard start >= normalizedLastPeriodStart else { return nil }
            return calendar.startOfDay(for: entry.endDate ?? entry.startDate)
        }.max()

        guard let latestOvulationEnd else { return summary.nextPeriodStart }
        return calendar.date(
            byAdding: .day,
            value: averageLutealPhaseLength(
                periodEntries: periodEntries,
                ovulationEntries: ovulationEntries,
                calendar: calendar
            ) ?? fallbackLutealPhaseLength,
            to: latestOvulationEnd
        )
    }

    static func preferredOvulationEntries(
        from entries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> [OvulationEntry] {
        Dictionary(grouping: entries) { entry in
            let components = calendar.dateComponents([.year, .month], from: entry.startDate)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        }.values.compactMap { monthEntries in
            monthEntries.max { $0.startDate < $1.startDate }
        }
    }

    static func isSupersededOvulation(
        _ entry: OvulationEntry,
        in entries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> Bool {
        let month = calendar.dateComponents([.year, .month], from: entry.startDate)
        return entries.contains { other in
            other !== entry
                && calendar.dateComponents([.year, .month], from: other.startDate) == month
                && other.startDate > entry.startDate
        }
    }

    static func averageLutealPhaseLength(
        periodEntries: [PeriodEntry],
        ovulationEntries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Int? {
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        let periodStarts = periodEntries
            .map { calendar.startOfDay(for: $0.startDate) }
            .filter { periodStart in
                cutoff.map { periodStart <= $0 } ?? true
            }
            .sorted()
        let eligibleOvulations = preferredOvulationEntries(from: ovulationEntries, calendar: calendar)
            .filter { entry in
                cutoff.map { calendar.startOfDay(for: entry.startDate) < $0 } ?? true
            }
        let lengths = eligibleOvulations.compactMap { entry -> Int? in
            let ovulationEnd = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            guard let precedingPeriod = periodStarts.last(where: { $0 <= ovulationEnd }),
                  let followingPeriod = periodStarts.first(where: { $0 > ovulationEnd }),
                  precedingPeriod < ovulationEnd,
                  let days = calendar.dateComponents([.day], from: ovulationEnd, to: followingPeriod).day,
                  days > 0 else { return nil }
            return days
        }

        guard !lengths.isEmpty else { return nil }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    static func averageOvulationLength(
        from entries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Int? {
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        let lengths = preferredOvulationEntries(from: entries, calendar: calendar).compactMap { entry -> Int? in
            let start = calendar.startOfDay(for: entry.startDate)
            guard cutoff.map({ start < $0 }) ?? true else { return nil }
            let end = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            guard end >= start else { return nil }
            return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        }

        guard !lengths.isEmpty else { return nil }
        return max(Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded()), 1)
    }

    static func estimatedPeriodEnd(
        startingOn startDate: Date,
        entries: [PeriodEntry],
        calendar: Calendar = .current
    ) -> Date {
        let periodLength = averagePeriodLength(from: entries, calendar: calendar) ?? fallbackPeriodLength
        return calendar.date(byAdding: .day, value: periodLength - 1, to: startDate) ?? startDate
    }
}
