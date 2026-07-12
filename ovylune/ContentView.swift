//
//  ContentView.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \PeriodEntry.startDate, order: .reverse) private var entries: [PeriodEntry]

    var body: some View {
        TabView {
            CalendarView(entries: entries)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            TrackView(entries: entries)
                .tabItem {
                    Label("Track", systemImage: "plus.circle")
                }

            PrivacyView()
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
        }
    }
}

private struct CalendarView: View {
    let entries: [PeriodEntry]

    private var summary: CycleSummary {
        CycleInsights.summary(for: entries)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthPager(entries: entries)
                }

                Section {
                    InsightGrid(summary: summary)

                    Text("Predictions are estimates for personal tracking only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listSectionSpacing(16)
            .navigationTitle("Calendar")
        }
    }
}

private struct TrackView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [PeriodEntry]

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var hasEndDate = true
    @State private var selectedSymptoms: Set<String> = []
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Log a period") {
                    DatePicker("Started", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, newValue in
                            endDate = max(endDate, newValue)
                        }

                    Toggle("Ended", isOn: $hasEndDate.animation())

                    if hasEndDate {
                        DatePicker("Ended on", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }

                    SymptomPicker(selection: $selectedSymptoms)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)

                    Button {
                        addEntry()
                    } label: {
                        Label("Save period", systemImage: "plus.circle.fill")
                    }
                    .disabled(hasEndDate && endDate < startDate)
                }

                Section("History") {
                    HistoryContent(entries: entries, deleteEntries: deleteEntries)
                }
            }
            .navigationTitle("Track")
            .toolbar {
                if !entries.isEmpty {
                    EditButton()
                }
            }
        }
    }

    private func addEntry() {
        let entry = PeriodEntry(
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            symptoms: Array(selectedSymptoms),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        modelContext.insert(entry)
        resetForm()
    }

    private func resetForm() {
        startDate = Date()
        endDate = Date()
        hasEndDate = true
        selectedSymptoms.removeAll()
        notes = ""
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
    }
}

private struct MonthPager: View {
    let entries: [PeriodEntry]

    @State private var selectedOffset = 0

    private let calendar = Calendar.current
    private let monthOffsets = Array(-120...120)

    var body: some View {
        TabView(selection: $selectedOffset) {
            ForEach(monthOffsets, id: \.self) { offset in
                MonthCalendar(
                    month: month(for: offset),
                    periodDays: periodDays
                )
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pagerHeight)
        .animation(.easeInOut(duration: 0.2), value: selectedOffset)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var pagerHeight: CGFloat {
        let displayedMonth = month(for: selectedOffset)
        let weekCount = calendar.range(of: .weekOfMonth, in: .month, for: displayedMonth)?.count ?? 6
        return CGFloat(weekCount * 45 + 13)
    }

    private var periodDays: Set<Date> {
        Set(entries.flatMap { entry in
            daysCovered(by: entry)
        })
    }

    private func month(for offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let currentMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        return calendar.date(byAdding: .month, value: offset, to: currentMonth) ?? currentMonth
    }

    private func daysCovered(by entry: PeriodEntry) -> [Date] {
        let start = calendar.startOfDay(for: entry.startDate)
        let end = calendar.startOfDay(for: entry.endDate ?? Date())
        let dayCount = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)

        return (0...dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}

private struct MonthCalendar: View {
    let month: Date
    let periodDays: Set<Date>

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            Text(month, format: .dateTime.month(.wide).year())
                .font(.headline)
                .frame(maxWidth: .infinity)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(calendarDays, id: \.id) { day in
                    DayCell(day: day, hasPeriod: day.date.map { periodDays.contains(calendar.startOfDay(for: $0)) } ?? false)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(.pink)
                    .frame(width: 8, height: 8)
                Text("Period logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        return Array(symbols[firstWeekdayIndex...]) + Array(symbols[..<firstWeekdayIndex])
    }

    private var calendarDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else { return [] }

        let dayCount = calendar.dateComponents([.day], from: firstWeek.start, to: lastWeek.end).day ?? 0

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstWeek.start) else {
                return nil
            }

            let isCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
            return CalendarDay(date: isCurrentMonth ? date : nil, placeholderIndex: offset)
        }
    }
}

private struct CalendarDay {
    let date: Date?
    let placeholderIndex: Int

    var id: String {
        if let date {
            return date.formatted(.iso8601.year().month().day())
        }

        return "placeholder-\(placeholderIndex)"
    }
}

private struct DayCell: View {
    let day: CalendarDay
    let hasPeriod: Bool

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            if hasPeriod {
                Circle()
                    .fill(.pink.opacity(0.18))
            }

            Text(dayNumber)
                .font(.subheadline.weight(hasPeriod ? .semibold : .regular))
                .foregroundStyle(hasPeriod ? .pink : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)

            if hasPeriod {
                Circle()
                    .fill(.pink)
                    .frame(width: 5, height: 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .opacity(day.date == nil ? 0 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayNumber: String {
        guard let date = day.date else { return "" }
        return String(calendar.component(.day, from: date))
    }

    private var accessibilityLabel: String {
        guard let date = day.date else { return "Empty day" }
        let formatted = date.formatted(.dateTime.month(.wide).day().year())
        return hasPeriod ? "\(formatted), period logged" : formatted
    }
}

private struct InsightGrid: View {
    let summary: CycleSummary

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                InsightTile(
                    title: "Cycle",
                    value: summary.averageCycleLength.map { "\($0) days" } ?? "28 days",
                    detail: summary.averageCycleLength == nil ? "Default estimate" : "Average"
                )

                InsightTile(
                    title: "Period",
                    value: summary.averagePeriodLength.map { "\($0) days" } ?? "5 days",
                    detail: summary.averagePeriodLength == nil ? "Default estimate" : "Average"
                )
            }

            GridRow {
                InsightTile(
                    title: "Last Period",
                    value: lastPeriodRange,
                    detail: "Logged locally"
                )

                InsightTile(
                    title: "Next Period",
                    value: nextPeriodRange,
                    detail: summary.nextPeriodStart == nil ? "Log a period" : "Estimate"
                )
            }
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private var lastPeriodRange: String {
        guard let start = summary.lastPeriodStart else { return "None" }
        return dateRange(from: start, to: summary.lastPeriodEnd)
    }

    private var nextPeriodRange: String {
        guard let start = summary.nextPeriodStart else { return "None" }
        let periodLength = summary.averagePeriodLength ?? CycleInsights.fallbackPeriodLength
        let end = Calendar.current.date(byAdding: .day, value: periodLength - 1, to: start)
        return dateRange(from: start, to: end)
    }

    private func dateRange(from start: Date, to end: Date?) -> String {
        let formattedStart = start.formatted(.dateTime.month(.abbreviated).day())

        guard let end else {
            return "\(formattedStart) - ongoing"
        }

        let formattedEnd = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(formattedStart) - \(formattedEnd)"
    }
}

private struct InsightTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SymptomPicker: View {
    @Binding var selection: Set<String>

    private let symptoms = [
        "Cramps",
        "Headache",
        "Fatigue",
        "Bloating",
        "Acne",
        "Tenderness",
        "Mood shifts",
        "Cravings"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Symptoms")
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(symptoms, id: \.self) { symptom in
                    Button {
                        toggle(symptom)
                    } label: {
                        Label(symptom, systemImage: selection.contains(symptom) ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ symptom: String) {
        if selection.contains(symptom) {
            selection.remove(symptom)
        } else {
            selection.insert(symptom)
        }
    }
}

private struct HistoryContent: View {
    let entries: [PeriodEntry]
    let deleteEntries: (IndexSet) -> Void

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "No periods logged",
                systemImage: "calendar.badge.plus",
                description: Text("Saved periods will appear here.")
            )
        } else {
            ForEach(entries) { entry in
                NavigationLink {
                    EntryDetailView(entry: entry)
                } label: {
                    EntryRow(entry: entry)
                }
            }
            .onDelete(perform: deleteEntries)
        }
    }
}

private struct EntryRow: View {
    let entry: PeriodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateRange)
                .font(.headline)

            if !entry.symptoms.isEmpty {
                Text(entry.symptoms.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateRange: String {
        let start = entry.startDate.formatted(.dateTime.month(.abbreviated).day().year())
        guard let endDate = entry.endDate else {
            return "\(start) - ongoing"
        }

        let end = endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) - \(end)"
    }
}

private struct EntryDetailView: View {
    @Bindable var entry: PeriodEntry
    @State private var selectedSymptoms: Set<String>
    @State private var hasEndDate: Bool

    init(entry: PeriodEntry) {
        self.entry = entry
        _selectedSymptoms = State(initialValue: Set(entry.symptoms))
        _hasEndDate = State(initialValue: entry.endDate != nil)
    }

    var body: some View {
        Form {
            Section("Dates") {
                DatePicker("Started", selection: $entry.startDate, displayedComponents: .date)

                Toggle("Ended", isOn: $hasEndDate.animation())
                    .onChange(of: hasEndDate) { _, newValue in
                        entry.endDate = newValue ? max(entry.endDate ?? entry.startDate, entry.startDate) : nil
                    }

                if hasEndDate {
                    DatePicker(
                        "Ended on",
                        selection: Binding(
                            get: { entry.endDate ?? entry.startDate },
                            set: { entry.endDate = max($0, entry.startDate) }
                        ),
                        in: entry.startDate...,
                        displayedComponents: .date
                    )
                }
            }

            Section {
                SymptomPicker(selection: $selectedSymptoms)
                    .onChange(of: selectedSymptoms) { _, newValue in
                        entry.symptoms = Array(newValue)
                    }
            }

            Section("Notes") {
                TextField("Notes", text: $entry.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle("Period")
    }
}

private struct PrivacyView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("No account", systemImage: "person.crop.circle.badge.xmark")
                    Label("No cloud sync", systemImage: "icloud.slash")
                    Label("No analytics", systemImage: "chart.bar.xaxis")
                    Label("No advertising trackers", systemImage: "hand.raised")
                } header: {
                    Text("Local only")
                } footer: {
                    Text("Ovylune stores your period history, symptoms, and notes on this device using local app storage.")
                }

                Section("Disclaimer") {
                    Text("Cycle predictions are estimates for informational and personal tracking only. Ovylune is not a medical device and should not be used for diagnosis, treatment, contraception, or other medical decisions.")
                }
            }
            .navigationTitle("Privacy")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PeriodEntry.self, inMemory: true)
}
