//
//  ContentView.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import SwiftData
import SwiftUI
import UIKit

private enum SelectableDates {
    static var range: ClosedRange<Date> {
        let calendar = Calendar.current
        let earliestDate = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!
        return earliestDate...Date()
    }

    static func ending(onOrAfter startDate: Date) -> ClosedRange<Date> {
        startDate...Date()
    }
}

struct ContentView: View {
    @Query(sort: \PeriodEntry.startDate, order: .reverse) private var entries: [PeriodEntry]
    @Query(sort: \OvulationEntry.startDate, order: .reverse) private var ovulationEntries: [OvulationEntry]

    private var ongoingPeriod: PeriodEntry? {
        entries.first { $0.endDate == nil }
    }

    var body: some View {
        TabView {
            CalendarView(entries: entries, ovulationEntries: ovulationEntries)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            TrackView(entries: entries, ovulationEntries: ovulationEntries)
                .tabItem {
                    Label("Track", systemImage: "plus.circle")
                }

            SettingsView(entries: entries, ovulationEntries: ovulationEntries)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .background(KeyboardDismissalView())
    }
}

private struct KeyboardDismissalView: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalUIView {
        KeyboardDismissalUIView()
    }

    func updateUIView(_ uiView: KeyboardDismissalUIView, context: Context) {}
}

private final class KeyboardDismissalUIView: UIView, UIGestureRecognizerDelegate {
    private lazy var dismissalRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
    private weak var installedWindow: UIWindow?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        installedWindow?.removeGestureRecognizer(dismissalRecognizer)
        installedWindow = window

        dismissalRecognizer.cancelsTouchesInView = false
        dismissalRecognizer.delegate = self
        window?.addGestureRecognizer(dismissalRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view

        while let view = touchedView {
            if view is UITextField || view is UITextView {
                return false
            }
            touchedView = view.superview
        }

        return true
    }

    @objc private func dismissKeyboard() {
        installedWindow?.endEditing(true)
    }

    deinit {
        installedWindow?.removeGestureRecognizer(dismissalRecognizer)
    }
}

private struct CalendarView: View {
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    @AppStorage(OvulationTracking.storageKey) private var isOvulationTrackingEnabled = true

    private var summary: CycleSummary {
        CycleInsights.summary(for: entries)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthPager(
                        entries: entries,
                        ovulationEntries: ovulationEntries,
                        isOvulationTrackingEnabled: isOvulationTrackingEnabled
                    )
                }

                Section {
                    InsightGrid(summary: summary)

                    Text("Predictions are estimates for personal tracking only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 28))
                }
            }
            .listSectionSpacing(16)
            .ongoingPeriodEditor(entries: entries, ovulationEntries: ovulationEntries)
        }
    }
}

private struct TrackView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]

    @State private var trackingMode = TrackingMode.period
    @AppStorage(OvulationTracking.storageKey) private var isOvulationTrackingEnabled = true

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var hasEndDate = true
    @State private var selectedSymptoms: Set<String> = []
    @State private var notes = ""
    @AppStorage(SymptomCatalog.storageKey) private var storedSymptoms = SymptomCatalog.defaultEncoded

    var body: some View {
        NavigationStack {
            Group {
                switch isOvulationTrackingEnabled ? trackingMode : .period {
                case .period:
                    periodContent
                case .ovulation:
                    OvulationTrackView(entries: ovulationEntries, periodEntries: entries)
                }
            }
            .ongoingPeriodEditor(entries: entries, ovulationEntries: ovulationEntries)
            .toolbar {
                if isOvulationTrackingEnabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Tracking type", selection: $trackingMode) {
                                ForEach(TrackingMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                        } label: {
                            Label(trackingMode.rawValue, systemImage: "chevron.down")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
            .onChange(of: isOvulationTrackingEnabled) { _, isEnabled in
                if !isEnabled {
                    trackingMode = .period
                }
            }
        }
    }

    private var periodContent: some View {
        List {
            Section {
                DatePicker("Started", selection: $startDate, in: SelectableDates.range, displayedComponents: .date)
                    .onChange(of: startDate) { _, newValue in
                        endDate = min(
                            CycleInsights.estimatedPeriodEnd(startingOn: newValue, entries: entries),
                            Date()
                        )
                    }

                Toggle("Ended", isOn: $hasEndDate.animation())

                if hasEndDate {
                    DatePicker(
                        "Ended on",
                        selection: $endDate,
                        in: SelectableDates.ending(onOrAfter: startDate),
                        displayedComponents: .date
                    )
                }

                if !availableSymptoms.isEmpty {
                    SymptomPicker(symptoms: availableSymptoms, selection: $selectedSymptoms)
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)

                if hasOverlapWarning {
                    VStack(alignment: .leading, spacing: 4) {
                        if overlapsExistingPeriod {
                            Label("These dates overlap a saved period.", systemImage: "exclamationmark.triangle.fill")
                        }
                        if overlapsExistingOvulation {
                            Label("These dates overlap a saved ovulation.", systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                } else {
                    Button {
                        addEntry()
                    } label: {
                        Label("Save period", systemImage: "plus.circle.fill")
                    }
                    .disabled(!canSave)
                }
            }

            Section {
                HistoryContent(entries: entries, ovulationEntries: ovulationEntries, deleteEntries: deleteEntries)
            }
        }
    }

    private var selectedEndDate: Date? {
        hasEndDate ? endDate : nil
    }

    private var availableSymptoms: [String] {
        SymptomCatalog.decode(storedSymptoms)
    }

    private var overlapsExistingPeriod: Bool {
        PeriodEntry.overlapsExisting(startDate: startDate, endDate: selectedEndDate, in: entries)
    }

    private var overlapsExistingOvulation: Bool {
        PeriodEntry.overlapsExisting(startDate: startDate, endDate: selectedEndDate, in: ovulationEntries)
    }

    private var hasOverlapWarning: Bool {
        overlapsExistingOvulation || overlapsExistingPeriod
    }

    private var canSave: Bool {
        (!hasEndDate || endDate >= startDate) && !hasOverlapWarning
    }

    private func addEntry() {
        guard canSave else { return }

        let entry = PeriodEntry(
            startDate: startDate,
            endDate: selectedEndDate,
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

private enum TrackingMode: String, CaseIterable, Identifiable {
    case period = "Period"
    case ovulation = "Ovulation"

    var id: Self { self }
}

private struct OvulationTrackView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [OvulationEntry]
    let periodEntries: [PeriodEntry]

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var multipleDays = false
    @State private var notes = ""

    var body: some View {
        List {
            Section {
                DatePicker("Started", selection: $startDate, in: SelectableDates.range, displayedComponents: .date)
                    .onChange(of: startDate) { _, newValue in
                        endDate = newValue
                    }

                Toggle("Multiple Days", isOn: $multipleDays.animation())

                if multipleDays {
                    DatePicker(
                        "Ended",
                        selection: $endDate,
                        in: SelectableDates.ending(onOrAfter: startDate),
                        displayedComponents: .date
                    )
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)

                if hasOverlapWarning {
                    VStack(alignment: .leading, spacing: 4) {
                        if overlapsExistingOvulation {
                            Label("These dates overlap a saved ovulation.", systemImage: "exclamationmark.triangle.fill")
                        }
                        if overlapsExistingPeriod {
                            Label("These dates overlap a saved period.", systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                } else {
                    Button {
                        addEntry()
                    } label: {
                        Label("Save ovulation", systemImage: "plus.circle.fill")
                    }
                }
            }

            Section {
                OvulationHistoryContent(entries: entries, periodEntries: periodEntries, deleteEntries: deleteEntries)
            }
        }
    }

    private var selectedEndDate: Date? {
        multipleDays ? endDate : nil
    }

    private var overlapsExistingOvulation: Bool {
        OvulationEntry.overlapsExisting(
            startDate: startDate,
            endDate: selectedEndDate,
            in: entries
        )
    }

    private var overlapsExistingPeriod: Bool {
        PeriodEntry.overlapsExisting(
            startDate: startDate,
            endDate: selectedEndDate ?? startDate,
            in: periodEntries
        )
    }

    private var hasOverlapWarning: Bool {
        overlapsExistingPeriod || overlapsExistingOvulation
    }

    private func addEntry() {
        guard !hasOverlapWarning else { return }
        modelContext.insert(OvulationEntry(
            startDate: startDate,
            endDate: selectedEndDate,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        startDate = Date()
        endDate = Date()
        multipleDays = false
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
    let ovulationEntries: [OvulationEntry]
    let isOvulationTrackingEnabled: Bool

    @State private var selectedOffset = 0
    @State private var furthestPredictedOffset = 0
    @State private var measuredHeights: [Int: CGFloat] = [:]

    private let calendar = Calendar.current
    private let monthOffsets = Array(-120...120)

    var body: some View {
        let loggedDays = periodDays
        let loggedOvulationDays = isOvulationTrackingEnabled ? ovulationDays : []
        let predictedDays = predictedPeriodDays
        let ovulationPrediction: (ovulationDays: Set<Date>, fertileDays: Set<Date>) =
            isOvulationTrackingEnabled ? predictedOvulation : ([], [])

        TabView(selection: $selectedOffset) {
            ForEach(monthOffsets, id: \.self) { offset in
                MonthCalendar(
                    month: month(for: offset),
                    periodDays: loggedDays,
                    ovulationDays: loggedOvulationDays,
                    predictedPeriodDays: predictedDays,
                    predictedOvulationDays: ovulationPrediction.ovulationDays,
                    predictedFertileDays: ovulationPrediction.fertileDays,
                    isOvulationTrackingEnabled: isOvulationTrackingEnabled
                )
                .padding(.vertical, 16)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    guard height > 0, measuredHeights[offset] != height else { return }
                    measuredHeights[offset] = height
                }
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pagerHeight)
        .animation(.easeInOut(duration: 0.2), value: selectedOffset)
        .onChange(of: selectedOffset) { _, newOffset in
            furthestPredictedOffset = max(furthestPredictedOffset, newOffset)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var pagerHeight: CGFloat {
        measuredHeights[selectedOffset] ?? 340
    }

    private var periodDays: Set<Date> {
        Set(entries.flatMap { entry in
            daysCovered(by: entry)
        })
    }

    private var predictedPeriodDays: Set<Date> {
        let summary = CycleInsights.summary(for: entries, calendar: calendar)
        let periodLength = summary.averagePeriodLength ?? CycleInsights.fallbackPeriodLength
        let cycleLength = summary.averageCycleLength ?? CycleInsights.fallbackCycleLength
        var days: Set<Date> = []

        if var predictedStart = summary.nextPeriodStart {
            while predictedStart < predictionWindow.start {
                guard let followingStart = calendar.date(
                    byAdding: .day,
                    value: cycleLength,
                    to: predictedStart
                ) else { break }
                predictedStart = followingStart
            }

            while predictedStart < predictionWindow.end {
                days.formUnion(
                    predictedDays(startingOn: predictedStart, length: periodLength)
                        .filter { predictionWindow.contains($0) }
                )

                guard let followingStart = calendar.date(
                    byAdding: .day,
                    value: cycleLength,
                    to: predictedStart
                ) else { break }
                predictedStart = followingStart
            }
        }

        if let ongoingEntry = entries.first(where: { $0.endDate == nil }) {
            days.formUnion(predictedDays(startingOn: ongoingEntry.startDate, length: periodLength))
        }

        return days
    }

    private var ovulationDays: Set<Date> {
        Set(ovulationEntries.flatMap { entry in
            let start = calendar.startOfDay(for: entry.startDate)
            let end = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            let dayCount = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)

            return (0...dayCount).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        })
    }

    private var predictedOvulation: (ovulationDays: Set<Date>, fertileDays: Set<Date>) {
        let summary = CycleInsights.summary(for: entries, calendar: calendar)
        let learnedInterval = CycleInsights.averageOvulationInterval(
            from: ovulationEntries,
            calendar: calendar
        )
        let predictionInterval = learnedInterval
            ?? summary.averageCycleLength
            ?? CycleInsights.fallbackCycleLength

        var ovulationDays: Set<Date> = []
        var fertileDays: Set<Date> = []

        for entry in ovulationEntries {
            let start = calendar.startOfDay(for: entry.startDate)
            let end = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            let dayCount = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)

            for offset in 0...dayCount {
                if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                    ovulationDays.insert(day)
                }
            }

            for offset in -CycleInsights.fertileDaysBeforeOvulation ..< 0 {
                if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                    fertileDays.insert(day)
                }
            }

            for offset in 1...CycleInsights.fertileDaysAfterOvulation {
                if let day = calendar.date(byAdding: .day, value: offset, to: end) {
                    fertileDays.insert(day)
                }
            }
        }

        guard var ovulationDate = CycleInsights.nextOvulationDate(
            from: ovulationEntries,
            nextPeriodStart: summary.nextPeriodStart,
            calendar: calendar
        ) else { return (ovulationDays, fertileDays) }

        while ovulationDate < predictionWindow.start {
            guard let followingDate = calendar.date(
                byAdding: .day,
                value: predictionInterval,
                to: ovulationDate
            ) else { return (ovulationDays, fertileDays) }
            ovulationDate = followingDate
        }

        while ovulationDate < predictionWindow.end {
            ovulationDays.insert(calendar.startOfDay(for: ovulationDate))

            for offset in -CycleInsights.fertileDaysBeforeOvulation...CycleInsights.fertileDaysAfterOvulation {
                guard offset != 0 else { continue }
                if let day = calendar.date(byAdding: .day, value: offset, to: ovulationDate),
                   predictionWindow.contains(day) {
                    fertileDays.insert(calendar.startOfDay(for: day))
                }
            }

            guard let followingDate = calendar.date(
                byAdding: .day,
                value: predictionInterval,
                to: ovulationDate
            ) else { break }
            ovulationDate = followingDate
        }

        return (ovulationDays, fertileDays)
    }

    private var predictionWindow: DateInterval {
        let currentMonth = month(for: 0)
        let start = calendar.dateInterval(of: .month, for: currentMonth)?.start ?? currentMonth
        let end = calendar.date(
            byAdding: .month,
            value: furthestPredictedOffset + 4,
            to: start
        ) ?? start
        return DateInterval(start: start, end: end)
    }

    private func predictedDays(startingOn startDate: Date, length: Int) -> Set<Date> {
        let start = calendar.startOfDay(for: startDate)
        return Set((0..<length).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
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
    let ovulationDays: Set<Date>
    let predictedPeriodDays: Set<Date>
    let predictedOvulationDays: Set<Date>
    let predictedFertileDays: Set<Date>
    let isOvulationTrackingEnabled: Bool

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
                    let date = day.date.map { calendar.startOfDay(for: $0) }
                    DayCell(
                        day: day,
                        hasPeriod: date.map(periodDays.contains) ?? false,
                        hasOvulation: date.map(ovulationDays.contains) ?? false,
                        isPredictedPeriod: date.map(predictedPeriodDays.contains) ?? false,
                        isPredictedOvulation: date.map(predictedOvulationDays.contains) ?? false,
                        isPredictedFertile: date.map(predictedFertileDays.contains) ?? false
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                legendItem(color: .pink, label: "Period logged")
                if isOvulationTrackingEnabled {
                    legendItem(color: .purple, label: "Ovulation logged")
                }
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
    let hasOvulation: Bool
    let isPredictedPeriod: Bool
    let isPredictedOvulation: Bool
    let isPredictedFertile: Bool

    private let calendar = Calendar.current

    private var isPeriodDay: Bool {
        hasPeriod || isPredictedPeriod
    }

    private var isHighlightedDay: Bool {
        isPeriodDay || isPredictedOvulation || isPredictedFertile
    }

    var body: some View {
        ZStack {
            if isPeriodDay {
                Circle()
                    .fill(.pink.opacity(0.18))
            } else if isPredictedOvulation {
                Circle()
                    .fill(.purple.opacity(0.16))
            } else if isPredictedFertile {
                Circle()
                    .fill(.blue.opacity(0.14))
            }

            Text(dayNumber)
                .font(.subheadline.weight(isHighlightedDay ? .semibold : .regular))
                .foregroundStyle(
                    isPeriodDay ? .pink
                        : isPredictedOvulation ? .purple
                        : isPredictedFertile ? .blue
                        : .primary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)

            if hasPeriod || hasOvulation {
                HStack(spacing: 2) {
                    if hasPeriod {
                        Circle()
                            .fill(.pink)
                            .frame(width: 5, height: 5)
                    }
                    if hasOvulation {
                        Circle()
                            .fill(.purple)
                            .frame(width: 5, height: 5)
                    }
                }
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
        if hasPeriod && hasOvulation { return "\(formatted), period and ovulation logged" }
        if hasPeriod { return "\(formatted), period logged" }
        if hasOvulation { return "\(formatted), ovulation logged" }
        if isPredictedPeriod { return "\(formatted), period predicted" }
        if isPredictedOvulation { return "\(formatted), ovulation predicted" }
        if isPredictedFertile { return "\(formatted), fertile window predicted" }
        return formatted
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
    let symptoms: [String]
    @Binding var selection: Set<String>

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
    let ovulationEntries: [OvulationEntry]
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
                    EntryDetailView(entry: entry, entries: entries, ovulationEntries: ovulationEntries)
                } label: {
                    EntryRow(entry: entry)
                }
            }
            .onDelete(perform: deleteEntries)
        }
    }
}

private struct OvulationHistoryContent: View {
    let entries: [OvulationEntry]
    let periodEntries: [PeriodEntry]
    let deleteEntries: (IndexSet) -> Void

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "No ovulations logged",
                systemImage: "calendar.badge.plus",
                description: Text("Saved ovulations will appear here.")
            )
        } else {
            ForEach(entries) { entry in
                NavigationLink {
                    OvulationEntryDetailView(entry: entry, entries: entries, periodEntries: periodEntries)
                } label: {
                    OvulationEntryRow(entry: entry)
                }
            }
            .onDelete(perform: deleteEntries)
        }
    }
}

private struct OvulationEntryRow: View {
    let entry: OvulationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateRange)
                .font(.headline)

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
        guard let endDate = entry.endDate else { return start }
        let end = endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) - \(end)"
    }
}

private struct OvulationEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: OvulationEntry
    let entries: [OvulationEntry]
    let periodEntries: [PeriodEntry]
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var multipleDays: Bool
    @State private var notes: String

    init(entry: OvulationEntry, entries: [OvulationEntry], periodEntries: [PeriodEntry]) {
        self.entry = entry
        self.entries = entries
        self.periodEntries = periodEntries
        _startDate = State(initialValue: entry.startDate)
        _endDate = State(initialValue: entry.endDate ?? entry.startDate)
        _multipleDays = State(initialValue: entry.endDate != nil)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        Form {
            Section("Dates") {
                DatePicker("Started", selection: $startDate, in: SelectableDates.range, displayedComponents: .date)
                    .onChange(of: startDate) { _, newValue in
                        endDate = newValue
                    }

                Toggle("Multiple Days", isOn: $multipleDays.animation())

                if multipleDays {
                    DatePicker(
                        "Ended",
                        selection: $endDate,
                        in: SelectableDates.ending(onOrAfter: startDate),
                        displayedComponents: .date
                    )
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }


            if hasOverlapWarning {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if overlapsExistingOvulation {
                            Label("These dates overlap a saved ovulation.", systemImage: "exclamationmark.triangle.fill")
                        }
                        if overlapsExistingPeriod {
                            Label("These dates overlap a saved period.", systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Ovulation")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(hasOverlapWarning)
            }
        }
    }

    private var selectedEndDate: Date? {
        multipleDays ? endDate : nil
    }

    private var overlapsExistingOvulation: Bool {
        OvulationEntry.overlapsExisting(
            startDate: startDate,
            endDate: selectedEndDate,
            in: entries,
            excluding: entry
        )
    }

    private var overlapsExistingPeriod: Bool {
        PeriodEntry.overlapsExisting(
            startDate: startDate,
            endDate: selectedEndDate ?? startDate,
            in: periodEntries
        )
    }

    private var hasOverlapWarning: Bool {
        overlapsExistingPeriod || overlapsExistingOvulation
    }

    private func save() {
        guard !hasOverlapWarning else { return }
        entry.startDate = startDate
        entry.endDate = selectedEndDate
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}

private struct EntryRow: View {
    let entry: PeriodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateRange)
                .font(.headline)

            Text(durationText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

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

    private var durationText: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: entry.startDate)
        let end = calendar.startOfDay(for: entry.endDate ?? Date())
        let days = max((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
        let unit = days == 1 ? "day" : "days"

        return entry.endDate == nil ? "\(days) \(unit) so far" : "\(days) \(unit)"
    }
}

private struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: PeriodEntry
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedSymptoms: Set<String>
    @State private var hasEndDate: Bool
    @State private var notes: String
    @AppStorage(SymptomCatalog.storageKey) private var storedSymptoms = SymptomCatalog.defaultEncoded

    init(entry: PeriodEntry, entries: [PeriodEntry], ovulationEntries: [OvulationEntry]) {
        self.entry = entry
        self.entries = entries
        self.ovulationEntries = ovulationEntries
        _startDate = State(initialValue: entry.startDate)
        _endDate = State(initialValue: entry.endDate ?? entry.startDate)
        _selectedSymptoms = State(initialValue: Set(entry.symptoms))
        _hasEndDate = State(initialValue: entry.endDate != nil)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        Form {
            Section("Dates") {
                DatePicker("Started", selection: $startDate, in: SelectableDates.range, displayedComponents: .date)
                    .onChange(of: startDate) { _, newValue in
                        endDate = max(endDate, newValue)
                    }

                Toggle("Ended", isOn: $hasEndDate.animation())

                if hasEndDate {
                    DatePicker(
                        "Ended on",
                        selection: $endDate,
                        in: SelectableDates.ending(onOrAfter: startDate),
                        displayedComponents: .date
                    )
                }
            }

            if !availableSymptoms.isEmpty {
                Section {
                    SymptomPicker(symptoms: availableSymptoms, selection: $selectedSymptoms)
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }


            if hasOverlapWarning {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if overlapsExistingPeriod {
                            Label("These dates overlap a saved period.", systemImage: "exclamationmark.triangle.fill")
                        }
                        if overlapsExistingOvulation {
                            Label("These dates overlap a saved ovulation.", systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Period")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(hasOverlapWarning)
            }
        }
    }

    private var selectedEndDate: Date? {
        hasEndDate ? endDate : nil
    }

    private var availableSymptoms: [String] {
        SymptomCatalog.decode(storedSymptoms)
    }

    private var overlapsExistingPeriod: Bool {
        PeriodEntry.overlapsExisting(
            startDate: startDate,
            endDate: selectedEndDate,
            in: entries,
            excluding: entry
        )
    }

    private var overlapsExistingOvulation: Bool {
        PeriodEntry.overlapsExisting(startDate: startDate, endDate: selectedEndDate, in: ovulationEntries)
    }

    private var hasOverlapWarning: Bool {
        overlapsExistingOvulation || overlapsExistingPeriod
    }

    private func save() {
        guard !hasOverlapWarning else { return }
        entry.startDate = startDate
        entry.endDate = selectedEndDate
        entry.symptoms = Array(selectedSymptoms)
        entry.notes = notes
        dismiss()
    }
}

private struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    @AppStorage(SymptomCatalog.storageKey) private var storedSymptoms = SymptomCatalog.defaultEncoded
    @AppStorage(OvulationTracking.storageKey) private var isOvulationTrackingEnabled = true
    @State private var newSymptom = ""
    @State private var isShowingDisableWarning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Enable Ovulation Tracking", isOn: ovulationTrackingBinding)
                }

                Section("Symptoms") {
                    HStack {
                        TextField("Add a symptom", text: $newSymptom)
                            .onSubmit(addSymptom)

                        Button("Add", action: addSymptom)
                            .disabled(!canAddSymptom)
                    }

                    ForEach(symptoms, id: \.self) { symptom in
                        Text(symptom)
                    }
                    .onDelete(perform: deleteSymptoms)
                }

                Section("Privacy") {
                    Label("No account required", systemImage: "person.crop.circle.badge.xmark")
                    Label("No data is uploaded", systemImage: "icloud.slash")
                    Label("No analytics collected", systemImage: "chart.bar.xaxis")
                    Label("No advertising trackers", systemImage: "hand.raised")

                    Text("Not a medical device. Do not use for diagnosis, treatment, contraception, or other medical decisions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .ongoingPeriodEditor(entries: entries, ovulationEntries: ovulationEntries)
            .alert("Disable Ovulation Tracking?", isPresented: $isShowingDisableWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Disable and Delete History", role: .destructive) {
                    disableOvulationTracking()
                }
            } message: {
                Text("Your ovulation history will be permanently deleted. Do you want to continue?")
            }
        }
    }

    private var ovulationTrackingBinding: Binding<Bool> {
        Binding(
            get: { isOvulationTrackingEnabled },
            set: { newValue in
                if newValue {
                    isOvulationTrackingEnabled = true
                } else if ovulationEntries.isEmpty {
                    isOvulationTrackingEnabled = false
                } else {
                    isShowingDisableWarning = true
                }
            }
        )
    }

    private func disableOvulationTracking() {
        for entry in ovulationEntries {
            modelContext.delete(entry)
        }
        isOvulationTrackingEnabled = false
    }

    private var symptoms: [String] {
        SymptomCatalog.decode(storedSymptoms)
    }

    private var trimmedNewSymptom: String {
        newSymptom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddSymptom: Bool {
        !trimmedNewSymptom.isEmpty && !symptoms.contains {
            $0.compare(trimmedNewSymptom, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func addSymptom() {
        guard canAddSymptom else { return }
        storedSymptoms = SymptomCatalog.encode(symptoms + [trimmedNewSymptom])
        newSymptom = ""
    }

    private func deleteSymptoms(at offsets: IndexSet) {
        var updatedSymptoms = symptoms
        updatedSymptoms.remove(atOffsets: offsets)
        storedSymptoms = SymptomCatalog.encode(updatedSymptoms)
    }
}

private enum OvulationTracking {
    static let storageKey = "isOvulationTrackingEnabled"
}

private enum SymptomCatalog {
    static let storageKey = "availableSymptoms"
    static let defaults = [
        "Cramps", "Headache", "Fatigue", "Bloating", "Tenderness", "Mood shifts"
    ]
    static let defaultEncoded = encode(defaults)

    static func encode(_ symptoms: [String]) -> String {
        guard let data = try? JSONEncoder().encode(symptoms),
              let encoded = String(data: data, encoding: .utf8)
        else { return "[]" }
        return encoded
    }

    static func decode(_ encoded: String) -> [String] {
        guard let data = encoded.data(using: .utf8),
              let symptoms = try? JSONDecoder().decode([String].self, from: data)
        else { return defaults }
        return symptoms
    }
}

private extension View {
    func ongoingPeriodEditor(entries: [PeriodEntry], ovulationEntries: [OvulationEntry]) -> some View {
        modifier(OngoingPeriodEditorModifier(entries: entries, ovulationEntries: ovulationEntries))
    }
}

private struct OngoingPeriodEditorModifier: ViewModifier {
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    @State private var editingPeriod: PeriodEntry?

    private var ongoingPeriod: PeriodEntry? {
        entries.first { $0.endDate == nil }
    }

    func body(content: Content) -> some View {
        content
        .toolbar {
            if let ongoingPeriod {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Ongoing Period") {
                        editingPeriod = ongoingPeriod
                    }
                }
            }
        }
        .navigationDestination(isPresented: isEditing) {
            if let editingPeriod {
                EntryDetailView(entry: editingPeriod, entries: entries, ovulationEntries: ovulationEntries)
            }
        }
    }

    private var isEditing: Binding<Bool> {
        Binding(
            get: { editingPeriod != nil },
            set: { isPresented in
                if !isPresented {
                    editingPeriod = nil
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PeriodEntry.self, OvulationEntry.self], inMemory: true)
}
