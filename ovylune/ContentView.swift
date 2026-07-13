//
//  ContentView.swift
//  ovylune
//
//  Created by Bailey Thompson on 2026-07-11.
//

import SwiftData
import SwiftUI
import UIKit

private let medicalDisclaimer = "Ovylune is intended for personal health, wellness, and symptom tracking. It is not a medical device and does not provide medical advice. Period, ovulation, and fertile day tracking is provided solely to record symptoms and notice cycle patterns; do not use it for pregnancy planning or contraception. Do not use it to diagnose, treat, cure, mitigate, or prevent any disease or condition, or to make other medical decisions. Estimates may be inaccurate. Consult a qualified healthcare professional before making medical decisions."

private struct MedicalDisclaimerText: View {
    var body: some View {
        Text(medicalDisclaimer)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

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
    @Query private var appSettings: [AppSettings]
    @Query private var storedEntries: [PeriodEntry]
    @Query private var storedOvulationEntries: [OvulationEntry]
    @Query private var storedIntimacyEntries: [IntimacyEntry]

    private var entries: [PeriodEntry] {
        storedEntries.sorted { $0.startDate > $1.startDate }
    }

    private var ovulationEntries: [OvulationEntry] {
        storedOvulationEntries.sorted { $0.startDate > $1.startDate }
    }

    private var intimacyEntries: [IntimacyEntry] {
        storedIntimacyEntries.sorted { $0.date > $1.date }
    }

    private var ongoingPeriod: PeriodEntry? {
        entries.first { $0.endDate == nil }
    }

    var body: some View {
        if let settings = appSettings.first {
            TabView {
                CalendarView(settings: settings, entries: entries, ovulationEntries: ovulationEntries, intimacyEntries: intimacyEntries)
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }

                TrackView(settings: settings, entries: entries, ovulationEntries: ovulationEntries, intimacyEntries: intimacyEntries)
                    .tabItem {
                        Label("Track", systemImage: "plus.circle")
                    }

                SettingsView(
                    settings: settings,
                    entries: entries,
                    ovulationEntries: ovulationEntries,
                    intimacyEntries: intimacyEntries
                )
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .background(KeyboardDismissalView())
        }
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
    let settings: AppSettings
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    let intimacyEntries: [IntimacyEntry]

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
                        intimacyEntries: intimacyEntries,
                        isOvulationTrackingEnabled: settings.isOvulationTrackingEnabled,
                        isIntimacyTrackingEnabled: settings.isIntimacyTrackingEnabled,
                        firstWeekday: settings.firstWeekday
                    )
                }

                Section {
                    InsightGrid(summary: summary)
                } footer: {
                    MedicalDisclaimerText()
                }
            }
            .listSectionSpacing(16)
            .ongoingPeriodEditor(settings: settings, entries: entries, ovulationEntries: ovulationEntries)
        }
    }
}

private struct TrackView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    let intimacyEntries: [IntimacyEntry]

    @State private var trackingMode = TrackingMode.period

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var hasEndDate = true
    @State private var selectedSymptoms: Set<String> = []
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Group {
                switch trackingMode {
                case .period:
                    periodContent
                case .ovulation:
                    OvulationTrackView(entries: ovulationEntries, periodEntries: entries)
                case .intimacy:
                    IntimacyTrackView(entries: intimacyEntries)
                }
            }
            .ongoingPeriodEditor(settings: settings, entries: entries, ovulationEntries: ovulationEntries)
            .toolbar {
                if availableTrackingModes.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Tracking type", selection: $trackingMode) {
                                ForEach(availableTrackingModes) { mode in
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
            .onChange(of: settings.isOvulationTrackingEnabled) { _, isEnabled in
                if !isEnabled && trackingMode == .ovulation {
                    trackingMode = .period
                }
            }
            .onChange(of: settings.isIntimacyTrackingEnabled) { _, isEnabled in
                if !isEnabled && trackingMode == .intimacy {
                    trackingMode = .period
                }
            }
        }
    }

    private var availableTrackingModes: [TrackingMode] {
        TrackingMode.allCases.filter { mode in
            (settings.isOvulationTrackingEnabled || mode != .ovulation)
                && (settings.isIntimacyTrackingEnabled || mode != .intimacy)
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
                HistoryContent(settings: settings, entries: entries, ovulationEntries: ovulationEntries, deleteEntries: deleteEntries)
            } footer: {
                MedicalDisclaimerText()
            }
        }
        .listSectionSpacing(16)
    }

    private var selectedEndDate: Date? {
        hasEndDate ? endDate : nil
    }

    private var availableSymptoms: [String] {
        settings.symptoms
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
    case intimacy = "Intimacy"

    var id: Self { self }
}

private struct IntimacyTrackView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [IntimacyEntry]

    @State private var date = Date()
    @State private var notes = ""

    var body: some View {
        List {
            Section {
                DatePicker("On", selection: $date, in: SelectableDates.range, displayedComponents: .date)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)

                Button {
                    addEntry()
                } label: {
                    Label("Save intimacy", systemImage: "plus.circle.fill")
                }
            }

            Section {
                IntimacyHistoryContent(entries: entries, deleteEntries: deleteEntries)
            } footer: {
                MedicalDisclaimerText()
            }
        }
        .listSectionSpacing(16)
    }

    private func addEntry() {
        modelContext.insert(IntimacyEntry(
            date: date,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        date = Date()
        notes = ""
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
    }
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
            } footer: {
                MedicalDisclaimerText()
            }
        }
        .listSectionSpacing(16)
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
    private struct MonthData {
        let periodDays: Set<Date>
        let ovulationDays: Set<Date>
        let intimacyDays: Set<Date>
        let estimatedPeriodDays: Set<Date>
        let estimatedOvulationDays: Set<Date>
        let estimatedFertileDays: Set<Date>
    }

    private struct EntryVersion: Hashable {
        let periods: [PeriodVersion]
        let ovulations: [OvulationVersion]
        let intimacies: [IntimacyVersion]
    }

    private struct PeriodVersion: Hashable {
        let startDate: Date
        let endDate: Date?
    }

    private struct OvulationVersion: Hashable {
        let startDate: Date
        let endDate: Date?
    }

    private struct IntimacyVersion: Hashable {
        let date: Date
    }

    private struct MonthKey: Hashable {
        let year: Int
        let month: Int
    }

    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    let intimacyEntries: [IntimacyEntry]
    let isOvulationTrackingEnabled: Bool
    let isIntimacyTrackingEnabled: Bool
    let firstWeekday: Int

    @State private var selectedOffset = 0
    @State private var loadedCenterOffset = 0
    @State private var measuredHeights: [MonthKey: CGFloat] = [:]
    @State private var cachedMonths: [MonthKey: MonthData] = [:]
    @State private var recenterTask: Task<Void, Never>?

    private let calendar = Calendar.current

    private var monthOffsets: [Int] {
        Array((loadedCenterOffset - 6)...(loadedCenterOffset + 6))
    }

    var body: some View {
        TabView(selection: $selectedOffset) {
            ForEach(monthOffsets, id: \.self) { offset in
                let displayedMonth = month(for: offset)
                let key = monthKey(for: displayedMonth)
                let data = cachedMonths[key] ?? makeMonthData(for: displayedMonth)
                MonthCalendar(
                    month: displayedMonth,
                    periodDays: data.periodDays,
                    ovulationDays: isOvulationTrackingEnabled ? data.ovulationDays : [],
                    intimacyDays: isIntimacyTrackingEnabled ? data.intimacyDays : [],
                    estimatedPeriodDays: data.estimatedPeriodDays,
                    estimatedOvulationDays: isOvulationTrackingEnabled ? data.estimatedOvulationDays : [],
                    estimatedFertileDays: isOvulationTrackingEnabled ? data.estimatedFertileDays : [],
                    isOvulationTrackingEnabled: isOvulationTrackingEnabled,
                    isIntimacyTrackingEnabled: isIntimacyTrackingEnabled,
                    firstWeekday: firstWeekday
                )
                .padding(.vertical, 16)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    guard height > 0, measuredHeights[key] != height else { return }
                    measuredHeights[key] = height
                }
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pagerHeight)
        .onAppear {
            synchronizeMonthCache()
        }
        .onChange(of: selectedOffset) { _, newOffset in
            scheduleRecenteringIfNeeded(for: newOffset)
        }
        .onChange(of: entryVersion) {
            cachedMonths.removeAll(keepingCapacity: true)
            synchronizeMonthCache()
        }
        .onDisappear {
            recenterTask?.cancel()
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var pagerHeight: CGFloat {
        // All month grids reserve six rows, so keep the pager at one shared
        // measured height while its selection changes during an interactive swipe.
        measuredHeights.values.max() ?? 340
    }

    private var entryVersion: EntryVersion {
        EntryVersion(
            periods: entries.map { PeriodVersion(startDate: $0.startDate, endDate: $0.endDate) },
            ovulations: ovulationEntries.map {
                OvulationVersion(startDate: $0.startDate, endDate: $0.endDate)
            },
            intimacies: intimacyEntries.map {
                IntimacyVersion(date: $0.date)
            }
        )
    }

    private func makeMonthData(for month: Date) -> MonthData {
        let window = monthWindow(for: month)
        let ovulationEstimate = estimatedOvulation(within: window)
        return MonthData(
            periodDays: periodDays(within: window),
            ovulationDays: ovulationDays(within: window),
            intimacyDays: intimacyDays(within: window),
            estimatedPeriodDays: estimatedPeriodDays(within: window),
            estimatedOvulationDays: ovulationEstimate.ovulationDays,
            estimatedFertileDays: ovulationEstimate.fertileDays
        )
    }

    private func synchronizeMonthCache() {
        let loadedMonths = monthOffsets.map { month(for: $0) }
        let loadedKeys = Set(loadedMonths.map(monthKey(for:)))
        var updatedCache = cachedMonths.filter { loadedKeys.contains($0.key) }
        measuredHeights = measuredHeights.filter { loadedKeys.contains($0.key) }

        for month in loadedMonths {
            let key = monthKey(for: month)
            if updatedCache[key] == nil {
                updatedCache[key] = makeMonthData(for: month)
            }
        }

        cachedMonths = updatedCache
    }

    private func scheduleRecenteringIfNeeded(for offset: Int) {
        recenterTask?.cancel()

        // Keep the TabView's children stable during ordinary swipes. Replacing
        // its page range while UIPageViewController is settling can make the
        // on-device pager visibly jump, especially when persisted data makes
        // each newly loaded month more expensive to build.
        guard abs(offset - loadedCenterOffset) >= 4 else { return }

        recenterTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, selectedOffset == offset else { return }
            loadedCenterOffset = offset
            synchronizeMonthCache()
        }
    }

    private func periodDays(within window: DateInterval) -> Set<Date> {
        Set(entries.flatMap { entry in
            daysCovered(by: entry, within: window)
        })
    }

    private func estimatedPeriodDays(within window: DateInterval) -> Set<Date> {
        let precisePeriodLength = CycleInsights.preciseAveragePeriodLength(from: entries, calendar: calendar)
            ?? Double(CycleInsights.fallbackPeriodLength)
        let periodLength = max(Int(precisePeriodLength.rounded()), 1)
        let cycleLength = max(
            CycleInsights.preciseAverageCycleLength(from: entries, calendar: calendar)
                ?? Double(CycleInsights.fallbackCycleLength),
            1
        )
        var days: Set<Date> = []

        if var estimatedStart = CycleInsights.nextPeriodStart(
               from: entries,
               ovulationEntries: ovulationEntries,
               calendar: calendar
           ) {
            let earliestOverlappingStart = calendar.date(
                byAdding: .day,
                value: -(periodLength - 1),
                to: window.start
            ) ?? window.start
            let estimateAnchor = estimatedStart
            estimatedStart = firstOccurrence(
                startingOn: estimateAnchor,
                interval: cycleLength,
                onOrAfter: earliestOverlappingStart
            )

            while estimatedStart < window.end {
                days.formUnion(
                    estimatedDays(
                        startingOn: estimatedStart,
                        length: periodLength,
                        within: window
                    )
                )

                guard let dayAfterEstimate = calendar.date(byAdding: .day, value: 1, to: estimatedStart) else { break }
                estimatedStart = firstOccurrence(
                    startingOn: estimateAnchor,
                    interval: cycleLength,
                    onOrAfter: dayAfterEstimate
                )
            }
        }

        if let ongoingEntry = entries.first(where: { $0.endDate == nil }) {
            days.formUnion(
                estimatedDays(
                    startingOn: ongoingEntry.startDate,
                    length: periodLength,
                    within: window
                )
            )
        }

        return days
    }

    private func ovulationDays(within window: DateInterval) -> Set<Date> {
        Set(ovulationEntries.flatMap { entry in
            let start = calendar.startOfDay(for: entry.startDate)
            let end = calendar.startOfDay(for: entry.endDate ?? entry.startDate)
            return days(from: start, through: end, within: window)
        })
    }

    private func intimacyDays(within window: DateInterval) -> Set<Date> {
        Set(intimacyEntries.compactMap { entry in
            let day = calendar.startOfDay(for: entry.date)
            return window.contains(day) ? day : nil
        })
    }

    private func estimatedOvulation(
        within window: DateInterval
    ) -> (ovulationDays: Set<Date>, fertileDays: Set<Date>) {
        let cycleLength = max(
            CycleInsights.preciseAverageCycleLength(from: entries, calendar: calendar)
                ?? Double(CycleInsights.fallbackCycleLength),
            1
        )
        let preferredOvulations = CycleInsights.preferredOvulationEntries(
            from: ovulationEntries,
            calendar: calendar
        )

        var ovulationDays: Set<Date> = []
        var fertileDays: Set<Date> = []
        var cycleStarts = entries.map { calendar.startOfDay(for: $0.startDate) }.sorted()
        guard let lastLoggedPeriod = cycleStarts.last else { return (ovulationDays, fertileDays) }
        var nextPeriod = CycleInsights.nextPeriodStart(
            from: entries,
            ovulationEntries: ovulationEntries,
            calendar: calendar
        ) ?? CycleInsights.nextEstimate(
            startingOn: lastLoggedPeriod,
            cycleLength: cycleLength,
            onOrAfter: calendar.date(byAdding: .day, value: 1, to: lastLoggedPeriod)!,
            calendar: calendar
        )

        let estimateAnchor = nextPeriod

        while nextPeriod <= window.end.addingTimeInterval(TimeInterval(cycleLength.rounded() * 86_400)) {
            cycleStarts.append(nextPeriod)
            guard let followingDay = calendar.date(byAdding: .day, value: 1, to: nextPeriod) else { break }
            nextPeriod = CycleInsights.nextEstimate(
                startingOn: estimateAnchor,
                cycleLength: cycleLength,
                onOrAfter: followingDay,
                calendar: calendar
            )
        }

        for (cycleStart, cycleEnd) in zip(cycleStarts, cycleStarts.dropFirst()) {
            let logged = preferredOvulations
                .filter {
                    let date = calendar.startOfDay(for: $0.startDate)
                    return date >= cycleStart && date < cycleEnd
                }
                .max { $0.startDate < $1.startDate }
            let estimatedEvent = CycleInsights.estimatedOvulationDate(
                cycleStart: cycleStart,
                nextPeriodStart: cycleEnd,
                periodEntries: entries,
                ovulationEntries: ovulationEntries,
                calendar: calendar
            )
            guard let ovulationEnd = logged.map({ calendar.startOfDay(for: $0.endDate ?? $0.startDate) })
                    ?? estimatedEvent else { continue }
            let ovulationStart = logged.map { calendar.startOfDay(for: $0.startDate) }
                ?? ovulationEnd

            ovulationDays.formUnion(days(from: ovulationStart, through: ovulationEnd, within: window))
            for offset in -CycleInsights.fertileDaysBeforeOvulation ..< 0 {
                if let day = calendar.date(byAdding: .day, value: offset, to: ovulationStart),
                   window.contains(day) { fertileDays.insert(calendar.startOfDay(for: day)) }
            }
            for offset in 1...CycleInsights.fertileDaysAfterOvulation {
                if let day = calendar.date(byAdding: .day, value: offset, to: ovulationEnd),
                   window.contains(day) { fertileDays.insert(calendar.startOfDay(for: day)) }
            }
        }

        return (ovulationDays, fertileDays)
    }

    private func monthWindow(for month: Date) -> DateInterval {
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func firstOccurrence(
        startingOn startDate: Date,
        interval: Double,
        onOrAfter targetDate: Date
    ) -> Date {
        CycleInsights.nextEstimate(
            startingOn: startDate,
            cycleLength: interval,
            onOrAfter: targetDate,
            calendar: calendar
        )
    }

    private func estimatedDays(
        startingOn startDate: Date,
        length: Int,
        within window: DateInterval
    ) -> Set<Date> {
        let start = calendar.startOfDay(for: startDate)
        guard length > 0,
              let end = calendar.date(byAdding: .day, value: length - 1, to: start) else {
            return []
        }
        return Set(days(from: start, through: end, within: window))
    }

    private func month(for offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let currentMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        return calendar.date(byAdding: .month, value: offset, to: currentMonth) ?? currentMonth
    }

    private func monthKey(for date: Date) -> MonthKey {
        let components = calendar.dateComponents([.year, .month], from: date)
        return MonthKey(year: components.year ?? 0, month: components.month ?? 0)
    }

    private func daysCovered(by entry: PeriodEntry, within window: DateInterval) -> [Date] {
        let start = calendar.startOfDay(for: entry.startDate)
        let end = calendar.startOfDay(for: entry.endDate ?? Date())
        return days(from: start, through: end, within: window)
    }

    private func days(from startDate: Date, through endDate: Date, within window: DateInterval) -> [Date] {
        let start = max(calendar.startOfDay(for: startDate), window.start)
        let inclusiveWindowEnd = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end
        let end = min(calendar.startOfDay(for: endDate), inclusiveWindowEnd)
        guard start <= end else { return [] }

        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        return (0...dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}

private struct MonthCalendar: View {
    let month: Date
    let periodDays: Set<Date>
    let ovulationDays: Set<Date>
    let intimacyDays: Set<Date>
    let estimatedPeriodDays: Set<Date>
    let estimatedOvulationDays: Set<Date>
    let estimatedFertileDays: Set<Date>
    let isOvulationTrackingEnabled: Bool
    let isIntimacyTrackingEnabled: Bool
    let firstWeekday: Int

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = firstWeekday
        return calendar
    }
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
                        hasIntimacy: date.map(intimacyDays.contains) ?? false,
                        isEstimatedPeriod: date.map(estimatedPeriodDays.contains) ?? false,
                        isEstimatedOvulation: date.map(estimatedOvulationDays.contains) ?? false,
                        isEstimatedFertile: date.map(estimatedFertileDays.contains) ?? false
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                legendItem(color: .pink, label: "Period logged")
                if isOvulationTrackingEnabled {
                    legendItem(color: .purple, label: "Ovulation logged")
                }
                if isIntimacyTrackingEnabled {
                    legendItem(color: .gray, label: "Intimacy logged")
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

        var days = (0..<dayCount).compactMap { offset -> CalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstWeek.start) else {
                return nil
            }

            let isCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
            return CalendarDay(date: isCurrentMonth ? date : nil, placeholderIndex: offset)
        }

        // Reserve six week rows for every month so shorter months leave their
        // unused space between the final week and the legend.
        days.append(contentsOf: (days.count..<42).map {
            CalendarDay(date: nil, placeholderIndex: $0)
        })

        return days
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
    let hasIntimacy: Bool
    let isEstimatedPeriod: Bool
    let isEstimatedOvulation: Bool
    let isEstimatedFertile: Bool

    @State private var isShowingStatus = false

    private let calendar = Calendar.current

    private var isPeriodDay: Bool {
        hasPeriod || isEstimatedPeriod
    }

    private var isHighlightedDay: Bool {
        isPeriodDay || isEstimatedOvulation || isEstimatedFertile
    }

    var body: some View {
        Button {
            isShowingStatus = !statusLabels.isEmpty
        } label: {
            ZStack {
                // Give highlighted and unhighlighted dates the same square layout
                // footprint. The decoration can then fill the cell without changing
                // the grid row's height.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)

                if isPeriodDay {
                    Circle()
                        .fill(.pink.opacity(0.18))
                } else if isEstimatedOvulation {
                    Circle()
                        .fill(.purple.opacity(0.16))
                } else if isEstimatedFertile {
                    Circle()
                        .fill(.blue.opacity(0.14))
                }

                Text(dayNumber)
                    .font(.subheadline.weight(isHighlightedDay ? .semibold : .regular))
                    .foregroundStyle(
                        isPeriodDay ? .pink
                            : isEstimatedOvulation ? .purple
                            : isEstimatedFertile ? .blue
                            : .primary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)

                if hasPeriod || hasOvulation || hasIntimacy {
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
                        if hasIntimacy {
                            Circle()
                                .fill(.gray)
                                .frame(width: 5, height: 5)
                        }
                    }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(statusLabels.isEmpty)
        .frame(maxWidth: .infinity)
        .opacity(day.date == nil ? 0 : 1)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $isShowingStatus, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(statusLabels, id: \.self) { label in
                    Text(label)
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var statusLabels: [String] {
        var labels: [String] = []

        if hasPeriod {
            labels.append("Period")
        } else if isEstimatedPeriod {
            labels.append("Period Estimate")
        }

        if hasOvulation {
            labels.append("Ovulation")
        } else if isEstimatedOvulation {
            labels.append("Ovulation Estimate")
        }

        if hasIntimacy {
            labels.append("Intimacy")
        }

        if isEstimatedFertile {
            labels.append("Estimate Fertile Day")
        }

        return labels
    }

    private var dayNumber: String {
        guard let date = day.date else { return "" }
        return String(calendar.component(.day, from: date))
    }

    private var accessibilityLabel: String {
        guard let date = day.date else { return "Empty day" }
        let formatted = date.formatted(.dateTime.month(.wide).day().year())
        let logged = [
            hasPeriod ? "period" : nil,
            hasOvulation ? "ovulation" : nil,
            hasIntimacy ? "intimacy" : nil
        ].compactMap { $0 }
        if !logged.isEmpty { return "\(formatted), \(logged.joined(separator: ", ")) logged" }
        if isEstimatedPeriod { return "\(formatted), period estimate" }
        if isEstimatedOvulation { return "\(formatted), ovulation estimate" }
        if isEstimatedFertile { return "\(formatted), estimated fertile day" }
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
                    detail: summary.cycleLengthsVary ? "Cycle lengths vary" : summary.cycleConfidence.label
                )

                InsightTile(
                    title: "Period",
                    value: summary.averagePeriodLength.map { "\($0) days" } ?? "5 days",
                    detail: summary.periodLengthsVary ? "Period lengths vary" : summary.periodConfidence.label
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
        guard let initialStart = summary.nextPeriodStart else { return "None" }
        let start = CycleInsights.nextEstimate(
            startingOn: initialStart,
            cycleLength: summary.averageCycleLength ?? CycleInsights.fallbackCycleLength,
            onOrAfter: Date()
        )
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
    let settings: AppSettings
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
                    EntryDetailView(settings: settings, entry: entry, entries: entries, ovulationEntries: ovulationEntries)
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
                    OvulationEntryRow(
                        entry: entry,
                        isSuperseded: CycleInsights.isSupersededOvulation(entry, in: entries)
                    )
                }
            }
            .onDelete(perform: deleteEntries)
        }
    }
}

private struct IntimacyHistoryContent: View {
    let entries: [IntimacyEntry]
    let deleteEntries: (IndexSet) -> Void

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "No intimacy logged",
                systemImage: "calendar.badge.plus",
                description: Text("Saved intimacy will appear here.")
            )
        } else {
            ForEach(entries) { entry in
                NavigationLink {
                    IntimacyEntryDetailView(entry: entry)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
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
            }
            .onDelete(perform: deleteEntries)
        }
    }
}

private struct IntimacyEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: IntimacyEntry
    @State private var date: Date
    @State private var notes: String

    init(entry: IntimacyEntry) {
        self.entry = entry
        _date = State(initialValue: entry.date)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        Form {
            Section("Date") {
                DatePicker("On", selection: $date, in: SelectableDates.range, displayedComponents: .date)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }

        }
        .listSectionSpacing(16)
        .navigationTitle("Intimacy")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
    }

    private func save() {
        entry.date = date
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}

private struct OvulationEntryRow: View {
    let entry: OvulationEntry
    let isSuperseded: Bool

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

            if entry.endDate != nil {
                Label(
                    "The last day is used for cycle calculations, following the standard model.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if isSuperseded {
                Label(
                    "A later ovulation is logged this cycle; this entry is not used for estimates.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
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
        .listSectionSpacing(16)
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
    let settings: AppSettings
    @Bindable var entry: PeriodEntry
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedSymptoms: Set<String>
    @State private var hasEndDate: Bool
    @State private var notes: String

    init(settings: AppSettings, entry: PeriodEntry, entries: [PeriodEntry], ovulationEntries: [OvulationEntry]) {
        self.settings = settings
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
        .listSectionSpacing(16)
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
        settings.symptoms
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
    @Bindable var settings: AppSettings
    let entries: [PeriodEntry]
    let ovulationEntries: [OvulationEntry]
    let intimacyEntries: [IntimacyEntry]
    @State private var newSymptom = ""
    @State private var isShowingDisableWarning = false
    @State private var isShowingIntimacyDisableWarning = false
    @State private var isShowingDeleteAllDataWarning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Start Day of Week", selection: $settings.firstWeekday) {
                        ForEach(WeekStart.values, id: \.self) { weekday in
                            Text(WeekStart.name(for: weekday)).tag(weekday)
                        }
                    }

                    Toggle("Enable Ovulation Tracking", isOn: ovulationTrackingBinding)
                    Toggle("Enable Intimacy Tracking", isOn: intimacyTrackingBinding)

                    Button("Delete All Data", role: .destructive) {
                        isShowingDeleteAllDataWarning = true
                    }
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

                Section {
                    Label("No account required", systemImage: "person.crop.circle.badge.xmark")
                    Label("No data is uploaded", systemImage: "icloud.slash")
                    Label("No analytics collected", systemImage: "chart.bar.xaxis")
                    Label("No advertising trackers", systemImage: "hand.raised")
                } header: {
                    Text("Privacy")
                }

                Section {
                    Text("Ovylune starts with general estimates of a 28-day cycle and a 5-day period. As you record your history, these estimates adapt to your patterns.")

                    Label("Recent observations are weighted more heavily.", systemImage: "clock.arrow.circlepath")
                    Label("Robust estimates reduce the effect of isolated unusual entries.", systemImage: "waveform.path.ecg")
                    Label("History and length-variation indicators help show the limits of each estimate.", systemImage: "chart.line.uptrend.xyaxis")

                    Label(
                        "Estimates may not accurately identify future periods, ovulation, or fertile days.",
                        systemImage: "exclamationmark.triangle"
                    )
                } header: {
                    Text("How Estimates Work")
                } footer: {
                    MedicalDisclaimerText()
                }
            }
            .listSectionSpacing(16)
            .ongoingPeriodEditor(settings: settings, entries: entries, ovulationEntries: ovulationEntries)
            .alert("Disable Ovulation Tracking?", isPresented: $isShowingDisableWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Disable and Delete History", role: .destructive) {
                    disableOvulationTracking()
                }
            } message: {
                Text("Your ovulation history will be permanently deleted. Do you want to continue?")
            }
            .alert("Disable Intimacy Tracking?", isPresented: $isShowingIntimacyDisableWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Disable and Delete History", role: .destructive) {
                    disableIntimacyTracking()
                }
            } message: {
                Text("Your intimacy history will be permanently deleted. Do you want to continue?")
            }
            .alert("Delete All Data?", isPresented: $isShowingDeleteAllDataWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All Data", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This will permanently delete all period, ovulation, and intimacy history, including symptoms and notes, and reset your settings. This action cannot be undone.")
            }
        }
    }

    private var ovulationTrackingBinding: Binding<Bool> {
        Binding(
            get: { settings.isOvulationTrackingEnabled },
            set: { newValue in
                if newValue {
                    settings.isOvulationTrackingEnabled = true
                } else if ovulationEntries.isEmpty {
                    settings.isOvulationTrackingEnabled = false
                } else {
                    isShowingDisableWarning = true
                }
            }
        )
    }

    private var intimacyTrackingBinding: Binding<Bool> {
        Binding(
            get: { settings.isIntimacyTrackingEnabled },
            set: { newValue in
                if newValue {
                    settings.isIntimacyTrackingEnabled = true
                } else if intimacyEntries.isEmpty {
                    settings.isIntimacyTrackingEnabled = false
                } else {
                    isShowingIntimacyDisableWarning = true
                }
            }
        )
    }

    private func disableOvulationTracking() {
        for entry in ovulationEntries {
            modelContext.delete(entry)
        }
        settings.isOvulationTrackingEnabled = false
    }

    private func disableIntimacyTracking() {
        for entry in intimacyEntries {
            modelContext.delete(entry)
        }
        settings.isIntimacyTrackingEnabled = false
    }

    private func deleteAllData() {
        for entry in entries {
            modelContext.delete(entry)
        }
        for entry in ovulationEntries {
            modelContext.delete(entry)
        }
        for entry in intimacyEntries {
            modelContext.delete(entry)
        }

        settings.reset()
        newSymptom = ""
    }

    private var symptoms: [String] {
        settings.symptoms
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
        settings.symptoms = symptoms + [trimmedNewSymptom]
        newSymptom = ""
    }

    private func deleteSymptoms(at offsets: IndexSet) {
        var updatedSymptoms = symptoms
        updatedSymptoms.remove(atOffsets: offsets)
        settings.symptoms = updatedSymptoms
    }
}

private enum WeekStart {
    static let values = Array(1...7)

    static func name(for weekday: Int, calendar: Calendar = .current) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }
}

private extension View {
    func ongoingPeriodEditor(settings: AppSettings, entries: [PeriodEntry], ovulationEntries: [OvulationEntry]) -> some View {
        modifier(OngoingPeriodEditorModifier(settings: settings, entries: entries, ovulationEntries: ovulationEntries))
    }
}

private struct OngoingPeriodEditorModifier: ViewModifier {
    let settings: AppSettings
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
                EntryDetailView(settings: settings, entry: editingPeriod, entries: entries, ovulationEntries: ovulationEntries)
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
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: AppSettings.self,
        PeriodEntry.self,
        OvulationEntry.self,
        IntimacyEntry.self,
        configurations: configuration
    )
    container.mainContext.insert(AppSettings())

    return ContentView()
        .modelContainer(container)
}
