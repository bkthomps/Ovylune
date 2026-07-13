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
    let cycleLengthsVary: Bool
    let periodLengthsVary: Bool
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
        case .low: "Little history available"
        case .medium: "Little history available"
        case .high: "Estimate"
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
    static let ovulationIntervalHalfLifeDays = 180.0
    static let lutealPhaseHalfLifeDays = 730.0

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
            cycleLengthsVary: lengthsVary(
                cycleDataPoints(from: recentEntries, calendar: calendar),
                maximumRegularRange: 9
            ),
            periodLengthsVary: lengthsVary(
                periodDataPoints(from: recentEntries, calendar: calendar),
                maximumRegularRange: 3
            ),
            nextPeriodStart: nextStart,
            lastPeriodStart: lastStart,
            lastPeriodEnd: lastEntry?.endDate
        )
    }

    static func lengthsVary(_ dataPoints: [Int], maximumRegularRange: Int) -> Bool {
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

    static func averageCycleLength(
        from entries: [PeriodEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Int? {
        preciseAverageCycleLength(from: entries, before: cutoffDate, calendar: calendar).map { Int($0.rounded()) }
    }

    static func preciseAverageCycleLength(
        from entries: [PeriodEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        let sortedStarts = entries
            .map { calendar.startOfDay(for: $0.startDate) }
            .filter { start in cutoff.map { start < $0 } ?? true }
            .sorted()

        guard sortedStarts.count >= 2 else { return nil }

        let gaps = zip(sortedStarts, sortedStarts.dropFirst()).compactMap { previous, current -> (value: Int, date: Date)? in
            guard let days = calendar.dateComponents([.day], from: previous, to: current).day else {
                return nil
            }
            return (days, current)
        }

        guard !gaps.isEmpty else { return nil }
        return personalizedWeightedMedian(
            of: gaps,
            halfLifeDays: cycleLengthHalfLifeDays,
            populationPrior: Double(fallbackCycleLength),
            calendar: calendar
        )
    }

    static func averagePeriodLength(
        from entries: [PeriodEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Int? {
        preciseAveragePeriodLength(from: entries, before: cutoffDate, calendar: calendar).map { Int($0.rounded()) }
    }

    static func preciseAveragePeriodLength(
        from entries: [PeriodEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        let lengths = entries.compactMap { entry -> (value: Int, date: Date)? in
            guard let endDate = entry.endDate else { return nil }
            let start = calendar.startOfDay(for: entry.startDate)
            let end = calendar.startOfDay(for: endDate)
            guard end >= start, cutoff.map({ end < $0 }) ?? true else { return nil }
            return ((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, start)
        }

        guard !lengths.isEmpty else { return nil }
        return personalizedWeightedMedian(
            of: lengths,
            halfLifeDays: periodLengthHalfLifeDays,
            populationPrior: Double(fallbackPeriodLength),
            calendar: calendar
        )
    }

    /// Uses calendar-time decay and a weighted median so isolated bad entries do
    /// not pull estimates far away from the user's usual pattern. Personal
    /// history gradually replaces the population prior over the first six
    /// reliable observations.
    private static func personalizedWeightedMedian(
        of observations: [(value: Int, date: Date)],
        halfLifeDays: Double,
        populationPrior: Double,
        calendar: Calendar
    ) -> Double? {
        guard let newestDate = observations.map(\.date).max(), halfLifeDays > 0 else { return nil }

        let weighted = observations.map { observation -> (value: Int, weight: Double) in
            let ageInDays = max(
                calendar.dateComponents([.day], from: observation.date, to: newestDate).day ?? 0,
                0
            )
            return (observation.value, pow(2, -Double(ageInDays) / halfLifeDays))
        }
        let sorted = weighted.sorted { $0.value < $1.value }
        let totalWeight = sorted.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        var cumulativeWeight = 0.0
        let personalEstimate = sorted.first { observation in
            cumulativeWeight += observation.weight
            return cumulativeWeight >= totalWeight / 2
        }.map { Double($0.value) } ?? Double(sorted.last!.value)
        let personalWeight = min(Double(observations.count) / 6.0, 1.0)
        return personalEstimate * personalWeight + populationPrior * (1 - personalWeight)
    }

    static func averageOvulationInterval(
        from entries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Int? {
        preciseAverageOvulationInterval(from: entries, before: cutoffDate, calendar: calendar).map { Int($0.rounded()) }
    }

    static func preciseAverageOvulationInterval(
        from entries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        let sortedStarts = entries
            .map { calendar.startOfDay(for: $0.startDate) }
            .filter { start in cutoff.map { start < $0 } ?? true }
            .sorted()

        guard sortedStarts.count >= 2 else { return nil }

        let gaps = zip(sortedStarts, sortedStarts.dropFirst()).compactMap { previous, current -> (value: Int, date: Date)? in
            guard let days = calendar.dateComponents([.day], from: previous, to: current).day else { return nil }
            return (days, current)
        }

        guard !gaps.isEmpty else { return nil }
        return personalizedWeightedMedian(
            of: gaps,
            halfLifeDays: ovulationIntervalHalfLifeDays,
            populationPrior: Double(fallbackCycleLength),
            calendar: calendar
        )
    }

    /// Days from a period start to the detected ovulation event. This remains a
    /// useful historical metric, but it does not drive calendar estimates because
    /// the pre-ovulation portion of a cycle is generally the more variable phase.
    static func preciseAverageOvulationInterval(
        periodEntries: [PeriodEntry],
        ovulationEntries: [OvulationEntry],
        before cutoffDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        let periodStarts = periodEntries
            .map { calendar.startOfDay(for: $0.startDate) }
            .filter { start in cutoff.map { start < $0 } ?? true }
            .sorted()
        let observations = preferredOvulationEntries(from: ovulationEntries, calendar: calendar)
            .compactMap { entry -> (value: Int, date: Date)? in
                let ovulationDate = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
                guard cutoff.map({ ovulationDate < $0 }) ?? true,
                      let periodStart = periodStarts.last(where: { $0 <= ovulationDate }),
                      let interval = calendar.dateComponents([.day], from: periodStart, to: ovulationDate).day,
                      interval > 0 else { return nil }
                return (interval, ovulationDate)
            }
        guard !observations.isEmpty else { return nil }
        return personalizedWeightedMedian(
            of: observations,
            halfLifeDays: ovulationIntervalHalfLifeDays,
            populationPrior: Double(fallbackCycleLength - fallbackLutealPhaseLength),
            calendar: calendar
        )
    }

    static func nextOvulationDate(
        from ovulationEntries: [OvulationEntry],
        nextPeriodStart: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let nextPeriodStart else { return nil }
        return calendar.date(
            byAdding: .day,
            value: -fallbackLutealPhaseLength,
            to: calendar.startOfDay(for: nextPeriodStart)
        )
    }

    /// Estimates ovulation backward from the following period. Only completed
    /// cycles before `cycleStart` may personalize the luteal phase; otherwise
    /// the general 14-day luteal-phase estimate is used.
    static func estimatedOvulationDate(
        cycleStart: Date,
        nextPeriodStart: Date,
        periodEntries: [PeriodEntry],
        ovulationEntries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> Date? {
        let lutealPhaseLength = preciseAverageLutealPhaseLength(
            periodEntries: periodEntries,
            ovulationEntries: ovulationEntries,
            before: cycleStart,
            calendar: calendar
        ) ?? Double(fallbackLutealPhaseLength)

        return addingRoundedDays(
            -lutealPhaseLength,
            to: calendar.startOfDay(for: nextPeriodStart),
            calendar: calendar
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
        let lengths = eligibleOvulations.compactMap { entry -> (value: Int, date: Date)? in
            let ovulationEnd = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            guard let precedingPeriod = periodStarts.last(where: { $0 <= ovulationEnd }),
                  let followingPeriod = periodStarts.first(where: { $0 > ovulationEnd }),
                  precedingPeriod < ovulationEnd,
                  let days = calendar.dateComponents([.day], from: ovulationEnd, to: followingPeriod).day,
                  days > 0 else { return nil }
            // The following period is when this observation becomes knowable.
            return (days, followingPeriod)
        }

        guard !lengths.isEmpty else { return nil }
        return personalizedWeightedMedian(
            of: lengths,
            halfLifeDays: lutealPhaseHalfLifeDays,
            populationPrior: Double(fallbackLutealPhaseLength),
            calendar: calendar
        )
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
        // Ovulation is modeled as a one-day event. Multi-day logged ranges may
        // describe detection/LH windows, but are not a biological duration to
        // learn and project into later cycles.
        let cutoff = cutoffDate.map { calendar.startOfDay(for: $0) }
        guard preferredOvulationEntries(from: entries, calendar: calendar).contains(where: { entry in
            cutoff.map { cutoffDay in
                calendar.startOfDay(for: entry.startDate) < cutoffDay
            } ?? true
        }) else { return nil }
        return 1
    }

    static func estimatedPeriodEnd(
        startingOn startDate: Date,
        entries: [PeriodEntry],
        calendar: Calendar = .current
    ) -> Date {
        let periodLength = preciseAveragePeriodLength(from: entries, calendar: calendar) ?? Double(fallbackPeriodLength)
        return addingRoundedDays(periodLength - 1, to: startDate, calendar: calendar) ?? startDate
    }

    static func nextEstimate(
        startingOn startDate: Date,
        cycleLength: Int,
        onOrAfter targetDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        nextEstimate(
            startingOn: startDate,
            cycleLength: Double(cycleLength),
            onOrAfter: targetDate,
            calendar: calendar
        )
    }

    static func nextEstimate(
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
