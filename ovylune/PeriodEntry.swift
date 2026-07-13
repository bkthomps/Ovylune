//
//  PeriodEntry.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import Foundation
import SwiftData

@Model
final class AppSettings {
    static let defaultSymptoms = [
        "Cramps", "Headache", "Fatigue", "Bloating", "Tenderness", "Mood shifts"
    ]

    var encryptedOvulationTrackingEnabled: Data
    var encryptedIntimacyTrackingEnabled: Data
    var encryptedFirstWeekday: Data
    var encryptedSymptoms: Data

    init(
        isOvulationTrackingEnabled: Bool = true,
        isIntimacyTrackingEnabled: Bool = true,
        firstWeekday: Int = 1,
        symptoms: [String] = AppSettings.defaultSymptoms
    ) {
        encryptedOvulationTrackingEnabled = EncryptedField.seal(isOvulationTrackingEnabled)
        encryptedIntimacyTrackingEnabled = EncryptedField.seal(isIntimacyTrackingEnabled)
        encryptedFirstWeekday = EncryptedField.seal(firstWeekday)
        encryptedSymptoms = EncryptedField.seal(symptoms)
    }

    var isOvulationTrackingEnabled: Bool {
        get { EncryptedField.open(Bool.self, from: encryptedOvulationTrackingEnabled) }
        set { encryptedOvulationTrackingEnabled = EncryptedField.seal(newValue) }
    }

    var isIntimacyTrackingEnabled: Bool {
        get { EncryptedField.open(Bool.self, from: encryptedIntimacyTrackingEnabled) }
        set { encryptedIntimacyTrackingEnabled = EncryptedField.seal(newValue) }
    }

    var firstWeekday: Int {
        get { EncryptedField.open(Int.self, from: encryptedFirstWeekday) }
        set { encryptedFirstWeekday = EncryptedField.seal(newValue) }
    }

    var symptoms: [String] {
        get {
            EncryptedField.open([String].self, from: encryptedSymptoms)
        }
        set {
            encryptedSymptoms = EncryptedField.seal(newValue)
        }
    }

    func reset() {
        isOvulationTrackingEnabled = true
        isIntimacyTrackingEnabled = true
        firstWeekday = 1
        symptoms = Self.defaultSymptoms
    }
}

@Model
final class PeriodEntry {
    var encryptedStartDate: Data
    var encryptedEndDate: Data
    var encryptedSymptoms: Data
    var encryptedNotes: Data
    var encryptedCreatedAt: Data

    init(startDate: Date, endDate: Date? = nil, symptoms: [String] = [], notes: String = "", createdAt: Date = .now) {
        encryptedStartDate = EncryptedField.seal(startDate)
        encryptedEndDate = EncryptedField.seal(endDate)
        encryptedSymptoms = EncryptedField.seal(symptoms.sorted())
        encryptedNotes = EncryptedField.seal(notes)
        encryptedCreatedAt = EncryptedField.seal(createdAt)
    }

    var startDate: Date {
        get { EncryptedField.open(Date.self, from: encryptedStartDate) }
        set { encryptedStartDate = EncryptedField.seal(newValue) }
    }

    var endDate: Date? {
        get { EncryptedField.open(Date?.self, from: encryptedEndDate) }
        set { encryptedEndDate = EncryptedField.seal(newValue) }
    }

    var notes: String {
        get { EncryptedField.open(String.self, from: encryptedNotes) }
        set { encryptedNotes = EncryptedField.seal(newValue) }
    }

    var createdAt: Date {
        get { EncryptedField.open(Date.self, from: encryptedCreatedAt) }
        set { encryptedCreatedAt = EncryptedField.seal(newValue) }
    }

    var symptoms: [String] {
        get {
            EncryptedField.open([String].self, from: encryptedSymptoms)
        }
        set {
            encryptedSymptoms = EncryptedField.seal(newValue.sorted())
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

    static func overlapsExisting(
        startDate: Date,
        endDate: Date?,
        in entries: [OvulationEntry],
        calendar: Calendar = .current
    ) -> Bool {
        let candidateStart = calendar.startOfDay(for: startDate)
        let candidateEnd = endDate.map { calendar.startOfDay(for: $0) }

        return entries.contains { entry in
            let existingStart = calendar.startOfDay(for: entry.startDate)
            let existingEnd = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            let startsBeforeCandidateEnds = candidateEnd.map { existingStart <= $0 } ?? true
            return startsBeforeCandidateEnds && candidateStart <= existingEnd
        }
    }
}

@Model
final class OvulationEntry {
    var encryptedStartDate: Data
    var encryptedEndDate: Data
    var encryptedNotes: Data
    var encryptedCreatedAt: Data

    init(startDate: Date, endDate: Date? = nil, notes: String = "", createdAt: Date = .now) {
        encryptedStartDate = EncryptedField.seal(startDate)
        encryptedEndDate = EncryptedField.seal(endDate)
        encryptedNotes = EncryptedField.seal(notes)
        encryptedCreatedAt = EncryptedField.seal(createdAt)
    }

    var startDate: Date {
        get { EncryptedField.open(Date.self, from: encryptedStartDate) }
        set { encryptedStartDate = EncryptedField.seal(newValue) }
    }

    var endDate: Date? {
        get { EncryptedField.open(Date?.self, from: encryptedEndDate) }
        set { encryptedEndDate = EncryptedField.seal(newValue) }
    }

    var notes: String {
        get { EncryptedField.open(String.self, from: encryptedNotes) }
        set { encryptedNotes = EncryptedField.seal(newValue) }
    }

    var createdAt: Date {
        get { EncryptedField.open(Date.self, from: encryptedCreatedAt) }
        set { encryptedCreatedAt = EncryptedField.seal(newValue) }
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

@Model
final class IntimacyEntry {
    var encryptedDate: Data
    var encryptedNotes: Data
    var encryptedCreatedAt: Data

    init(date: Date, notes: String = "", createdAt: Date = .now) {
        encryptedDate = EncryptedField.seal(date)
        encryptedNotes = EncryptedField.seal(notes)
        encryptedCreatedAt = EncryptedField.seal(createdAt)
    }

    var date: Date {
        get { EncryptedField.open(Date.self, from: encryptedDate) }
        set { encryptedDate = EncryptedField.seal(newValue) }
    }

    var notes: String {
        get { EncryptedField.open(String.self, from: encryptedNotes) }
        set { encryptedNotes = EncryptedField.seal(newValue) }
    }

    var createdAt: Date {
        get { EncryptedField.open(Date.self, from: encryptedCreatedAt) }
        set { encryptedCreatedAt = EncryptedField.seal(newValue) }
    }
}
