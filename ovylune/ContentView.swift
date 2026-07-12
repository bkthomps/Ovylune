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
            DashboardView(entries: entries)
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }

            HistoryView(entries: entries)
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            PrivacyView()
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
        }
    }
}

private struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [PeriodEntry]

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var hasEndDate = true
    @State private var selectedSymptoms: Set<String> = []
    @State private var notes = ""

    private var summary: CycleSummary {
        CycleInsights.summary(for: entries)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    InsightGrid(summary: summary)
                }

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

                Section("Estimate") {
                    if let nextPeriodStart = summary.nextPeriodStart {
                        LabeledContent("Next period") {
                            Text(nextPeriodStart, format: .dateTime.month(.abbreviated).day().year())
                                .fontWeight(.semibold)
                        }
                    } else {
                        Text("Log at least one period to see an upcoming estimate.")
                            .foregroundStyle(.secondary)
                    }

                    Text("Predictions are estimates for personal tracking only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ovylune")
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
                    title: "Last start",
                    value: summary.lastPeriodStart.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "None",
                    detail: "Logged locally"
                )
                .gridCellColumns(2)
            }
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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

private struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [PeriodEntry]

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("History")
            .toolbar {
                if !entries.isEmpty {
                    EditButton()
                }
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
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
