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
}

