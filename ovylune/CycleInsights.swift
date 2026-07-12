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
    let cycleConfidence: EstimateConfidence
    let periodConfidence: EstimateConfidence
    let isCycleIrregular: Bool
    let isPeriodLengthIrregular: Bool
    let nextPeriodStart: Date?
    let lastPeriodStart: Date?
    let lastPeriodEnd: Date?
}

enum EstimateConfidence: Equatable {
    case defaultEstimate
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .defaultEstimate: "Default estimate"
        case .low: "Low Confidence"
        case .medium: "Medium Confidence"
        case .high: "High Confidence"
        }
    }
}

enum CycleInsights {
    static let fallbackCycleLength = 28
    static let fallbackPeriodLength = 5
    static let fallbackTimeBetweenPeriods = fallbackCycleLength - fallbackPeriodLength
    static let fallbackLutealPhaseLength = 14
    static let fertileDaysBeforeOvulation = 5
    static let fertileDaysAfterOvulation = 1
    static let cycleLengthHalfLifeDays = 365.0
    static let periodLengthHalfLifeDays = 730.0

    static func summary(for entries: [PeriodEntry], calendar: Calendar = .current) -> CycleSummary {
        let sorted = entries.sorted { $0.startDate < $1.startDate }
        let averageCycleLength = averageCycleLength(from: sorted, calendar: calendar)
        let averagePeriodLength = averagePeriodLength(from: sorted, calendar: calendar)
        let allCycleDataPoints = cycleDataPoints(from: sorted, calendar: calendar)
        let allPeriodDataPoints = periodDataPoints(from: sorted, calendar: calendar)
        let recentEntries = entriesFromLatestYear(sorted, calendar: calendar)
        let lastEntry = sorted.last
        let lastStart = lastEntry?.startDate
        let nextStart = lastStart.flatMap {
            addingRoundedDays(
                preciseAverageCycleLength(from: sorted, calendar: calendar) ?? Double(fallbackCycleLength),
                to: calendar.startOfDay(for: $0),
                calendar: calendar
            )
        }

        return CycleSummary(
            averageCycleLength: averageCycleLength,
            averagePeriodLength: averagePeriodLength,
            cycleConfidence: confidence(for: averageCycleLength, dataPoints: allCycleDataPoints, mediumVariation: 2, lowVariation: 5),
            periodConfidence: confidence(for: averagePeriodLength, dataPoints: allPeriodDataPoints, mediumVariation: 1, lowVariation: 2),
            isCycleIrregular: isIrregular(
                cycleDataPoints(from: recentEntries, calendar: calendar),
                maximumRegularRange: 9
            ),
            isPeriodLengthIrregular: isIrregular(
                periodDataPoints(from: recentEntries, calendar: calendar),
                maximumRegularRange: 3
            ),
            nextPeriodStart: nextStart,
            lastPeriodStart: lastStart,
            lastPeriodEnd: lastEntry?.endDate
        )
    }

    static func isIrregular(_ dataPoints: [Int], maximumRegularRange: Int) -> Bool {
        guard dataPoints.count >= 3,
              let shortest = dataPoints.min(),
              let longest = dataPoints.max() else {
            return false
        }
        return longest - shortest > maximumRegularRange
    }

    private static func entriesFromLatestYear(
        _ entries: [PeriodEntry],
        calendar: Calendar
    ) -> [PeriodEntry] {
        guard let latestStart = entries.map(\.startDate).max(),
              let cutoff = calendar.date(byAdding: .year, value: -1, to: latestStart) else {
            return []
        }
        return entries.filter { $0.startDate >= cutoff }
    }

    static func confidence(
        for estimate: Int?,
        dataPoints: [Int],
        mediumVariation: Double,
        lowVariation: Double
    ) -> EstimateConfidence {
        guard estimate != nil, !dataPoints.isEmpty else { return .defaultEstimate }

        let countLevel: Int
        switch dataPoints.count {
        case 1...2: countLevel = 1
        case 3...5: countLevel = 2
        default: countLevel = 3
        }

        let mean = Double(dataPoints.reduce(0, +)) / Double(dataPoints.count)
        let variance = dataPoints.reduce(0.0) { result, value in
            result + pow(Double(value) - mean, 2)
        } / Double(dataPoints.count)
        let variation = sqrt(variance)
        let regularityLevel = variation <= mediumVariation ? 3 : (variation <= lowVariation ? 2 : 1)

        switch min(countLevel, regularityLevel) {
        case 1: return .low
        case 2: return .medium
        default: return .high
        }
    }

    private static func cycleDataPoints(from entries: [PeriodEntry], calendar: Calendar) -> [Int] {
        if entries.count == 1 {
            guard let periodLength = periodDataPoints(from: entries, calendar: calendar).first else { return [] }
            return [periodLength + fallbackTimeBetweenPeriods]
        }

        let starts = entries.map { calendar.startOfDay(for: $0.startDate) }.sorted()
        return zip(starts, starts.dropFirst()).compactMap { previous, current in
            calendar.dateComponents([.day], from: previous, to: current).day
        }
    }

    private static func periodDataPoints(from entries: [PeriodEntry], calendar: Calendar) -> [Int] {
        entries.compactMap { entry in
            guard let endDate = entry.endDate else { return nil }
            let start = calendar.startOfDay(for: entry.startDate)
            let end = calendar.startOfDay(for: endDate)
            guard end >= start else { return nil }
            return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        }
    }

    static func averageCycleLength(from entries: [PeriodEntry], calendar: Calendar = .current) -> Int? {
        preciseAverageCycleLength(from: entries, calendar: calendar).map { Int($0.rounded()) }
    }

    static func preciseAverageCycleLength(from entries: [PeriodEntry], calendar: Calendar = .current) -> Double? {
        let sortedStarts = entries
            .map { calendar.startOfDay(for: $0.startDate) }
            .sorted()

        if sortedStarts.count == 1 {
            guard let periodLength = preciseAveragePeriodLength(from: entries, calendar: calendar) else {
                return nil
            }
            return periodLength + Double(fallbackTimeBetweenPeriods)
        }

        guard sortedStarts.count >= 2 else { return nil }

        let gaps = zip(sortedStarts, sortedStarts.dropFirst()).compactMap { previous, current -> (value: Int, date: Date)? in
            guard let days = calendar.dateComponents([.day], from: previous, to: current).day else {
                return nil
            }
            return (days, current)
        }

        guard !gaps.isEmpty else { return nil }
        return recencyWeightedAverage(
            of: gaps,
            halfLifeDays: cycleLengthHalfLifeDays,
            calendar: calendar
        )
    }

    static func averagePeriodLength(from entries: [PeriodEntry], calendar: Calendar = .current) -> Int? {
        preciseAveragePeriodLength(from: entries, calendar: calendar).map { Int($0.rounded()) }
    }

    static func preciseAveragePeriodLength(from entries: [PeriodEntry], calendar: Calendar = .current) -> Double? {
        let lengths = entries.compactMap { entry -> (value: Int, date: Date)? in
            guard let endDate = entry.endDate else { return nil }
            let start = calendar.startOfDay(for: entry.startDate)
            let end = calendar.startOfDay(for: endDate)
            guard end >= start else { return nil }
            return ((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, start)
        }

        guard !lengths.isEmpty else { return nil }
        return recencyWeightedAverage(
            of: lengths,
            halfLifeDays: periodLengthHalfLifeDays,
            calendar: calendar
        )
    }

    private static func recencyWeightedAverage(
        of observations: [(value: Int, date: Date)],
        halfLifeDays: Double,
        calendar: Calendar
    ) -> Double? {
        guard let newestDate = observations.map(\.date).max(), halfLifeDays > 0 else { return nil }

        let weighted = observations.reduce(into: (sum: 0.0, weight: 0.0)) { result, observation in
            let ageInDays = max(
                calendar.dateComponents([.day], from: observation.date, to: newestDate).day ?? 0,
                0
            )
            let weight = pow(0.5, Double(ageInDays) / halfLifeDays)
            result.sum += Double(observation.value) * weight
            result.weight += weight
        }

        guard weighted.weight > 0 else { return nil }
        return weighted.sum / weighted.weight
    }

    static func averageOvulationInterval(
        from entries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> Int? {
        preciseAverageOvulationInterval(from: entries, calendar: calendar).map { Int($0.rounded()) }
    }

    static func preciseAverageOvulationInterval(
        from entries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> Double? {
        let sortedStarts = entries
            .map { calendar.startOfDay(for: $0.startDate) }
            .sorted()

        guard sortedStarts.count >= 2 else { return nil }

        let gaps = zip(sortedStarts, sortedStarts.dropFirst()).compactMap { previous, current in
            calendar.dateComponents([.day], from: previous, to: current).day
        }

        guard !gaps.isEmpty else { return nil }
        return Double(gaps.reduce(0, +)) / Double(gaps.count)
    }

    static func nextOvulationDate(
        from ovulationEntries: [OvulationEntry],
        nextPeriodStart: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        if let interval = preciseAverageOvulationInterval(from: ovulationEntries, calendar: calendar),
           let latest = ovulationEntries.map(\.startDate).max() {
            return addingRoundedDays(
                interval,
                to: calendar.startOfDay(for: latest),
                calendar: calendar
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
        return addingRoundedDays(
            preciseAverageLutealPhaseLength(
                periodEntries: periodEntries,
                ovulationEntries: ovulationEntries,
                calendar: calendar
            ) ?? Double(fallbackLutealPhaseLength),
            to: latestOvulationEnd,
            calendar: calendar
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
        preciseAverageLutealPhaseLength(
            periodEntries: periodEntries,
            ovulationEntries: ovulationEntries,
            before: cutoffDate,
            calendar: calendar
        ).map { Int($0.rounded()) }
    }

    static func preciseAverageLutealPhaseLength(
        periodEntries: [PeriodEntry],
        ovulationEntries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Double? {
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
        return Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    static func averageOvulationLength(
        from entries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Int? {
        preciseAverageOvulationLength(from: entries, before: cutoffDate, calendar: calendar)
            .map { max(Int($0.rounded()), 1) }
    }

    static func preciseAverageOvulationLength(
        from entries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        let lengths = preferredOvulationEntries(from: entries, calendar: calendar).compactMap { entry -> Int? in
            let start = calendar.startOfDay(for: entry.startDate)
            guard cutoff.map({ start < $0 }) ?? true else { return nil }
            let end = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            guard end >= start else { return nil }
            return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        }

        guard !lengths.isEmpty else { return nil }
        return Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    static func estimatedPeriodEnd(
        startingOn startDate: Date,
        entries: [PeriodEntry],
        calendar: Calendar = .current
    ) -> Date {
        let periodLength = preciseAveragePeriodLength(from: entries, calendar: calendar) ?? Double(fallbackPeriodLength)
        return addingRoundedDays(periodLength - 1, to: startDate, calendar: calendar) ?? startDate
    }

    static func nextPrediction(
        startingOn startDate: Date,
        cycleLength: Int,
        onOrAfter targetDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        nextPrediction(
            startingOn: startDate,
            cycleLength: Double(cycleLength),
            onOrAfter: targetDate,
            calendar: calendar
        )
    }

    static func nextPrediction(
        startingOn startDate: Date,
        cycleLength: Double,
        onOrAfter targetDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: targetDate)
        let interval = max(cycleLength, 1)
        guard start < target else { return start }

        let elapsedDays = max(
            calendar.dateComponents([.day], from: start, to: target).day ?? 0,
            0
        )
        var occurrence = max(Int(floor(Double(elapsedDays) / interval)), 0)
        var result = addingRoundedDays(Double(occurrence) * interval, to: start, calendar: calendar) ?? start

        if result < target {
            occurrence += 1
            result = addingRoundedDays(Double(occurrence) * interval, to: start, calendar: calendar) ?? result
        }
        return result
    }

    private static func addingRoundedDays(
        _ days: Double,
        to date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(byAdding: .day, value: Int(days.rounded()), to: date)
    }
}
