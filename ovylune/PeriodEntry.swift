//
//  PeriodEntry.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import Foundation
import SwiftData

@Model
final class PeriodEntry {
    var startDate: Date
    var endDate: Date?
    var symptomTagsRaw: String
    var notes: String
    var createdAt: Date

    init(startDate: Date, endDate: Date? = nil, symptoms: [String] = [], notes: String = "", createdAt: Date = .now) {
        self.startDate = startDate
        self.endDate = endDate
        self.symptomTagsRaw = symptoms.sorted().joined(separator: ",")
        self.notes = notes
        self.createdAt = createdAt
    }

    var symptoms: [String] {
        get {
            symptomTagsRaw
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
        }
        set {
            symptomTagsRaw = newValue.sorted().joined(separator: ",")
        }
    }

    static func overlapsExisting(
        startDate: Date,
        endDate: Date?,
        in entries: [PeriodEntry],
        excluding excludedEntry: PeriodEntry? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        let candidateStart = calendar.startOfDay(for: startDate)
        let candidateEnd = endDate.map { calendar.startOfDay(for: $0) }

        return entries.contains { entry in
            guard entry !== excludedEntry else { return false }

            let existingStart = calendar.startOfDay(for: entry.startDate)
            let existingEnd = entry.endDate.map { calendar.startOfDay(for: $0) }
            let startsBeforeCandidateEnds = candidateEnd.map { existingStart <= $0 } ?? true
            let candidateStartsBeforeEnd = existingEnd.map { candidateStart <= $0 } ?? true
            return startsBeforeCandidateEnds && candidateStartsBeforeEnd
        }
    }
}

@Model
final class OvulationEntry {
    var startDate: Date
    var endDate: Date?
    var notes: String
    var createdAt: Date

    init(startDate: Date, endDate: Date? = nil, notes: String = "", createdAt: Date = .now) {
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.createdAt = createdAt
    }

    static func overlapsExisting(
        startDate: Date,
        endDate: Date?,
        in entries: [OvulationEntry],
        excluding excludedEntry: OvulationEntry? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        let candidateStart = calendar.startOfDay(for: startDate)
        let candidateEnd = calendar.startOfDay(for: endDate ?? startDate)

        return entries.contains { entry in
            guard entry !== excludedEntry else { return false }

            let existingStart = calendar.startOfDay(for: entry.startDate)
            let existingEnd = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            return existingStart <= candidateEnd && candidateStart <= existingEnd
        }
    }
}
