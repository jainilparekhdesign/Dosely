import SwiftData
import SwiftUI

struct MedicationDetailView: View {
    @Bindable var medication: Medication
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var refillAmount: Double = 30
    @State private var showRefill = false
    @State private var showPhoto = false
    @State private var stats = AdherenceStats()

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Button { if medication.photoData != nil { showPhoto = true } } label: {
                        MedicationThumb(med: medication, size: 96)
                    }
                    .buttonStyle(.plain)
                    VStack(spacing: 4) {
                        Text(medication.name).font(.title2.bold()).multilineTextAlignment(.center)
                        if !medication.genericName.isEmpty {
                            Text(medication.genericName).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text([medication.strength, medication.type.label].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if medication.isCritical {
                        Label("Critical medicine — louder reminders", systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.doseMissed)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Schedule") {
                let s = medication.schedule
                LabeledContent("How often", value: s.frequencyText(medication.mealTimes))
                if s.isTimed {
                    ForEach(s.pattern == .everyXHours ? Array(s.times.prefix(1)) : s.times.sorted { $0.resolvedMinutes(medication.mealTimes) < $1.resolvedMinutes(medication.mealTimes) }) { t in
                        LabeledContent {
                            Text(Fmt.dose(t.amount, unit: medication.unit))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(Fmt.time(minutes: t.resolvedMinutes(medication.mealTimes)))
                                if t.anchor != nil { Text(t.label(medication.mealTimes)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } else {
                    LabeledContent("Dose", value: Fmt.dose(s.times.first?.amount ?? 1, unit: medication.unit))
                }
                if s.foodTiming != .any { LabeledContent("Food", value: s.foodTiming.label) }
                LabeledContent("Started", value: s.startDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Ends", value: s.endDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Ongoing")
                if let d = s.durationText() { LabeledContent("Course", value: d) }
            }

            if s_isTimed {
                Section("Last 30 days") {
                    HStack(spacing: 16) {
                        ZStack {
                            ProgressRing(progress: stats.rate ?? 0, lineWidth: 7, color: color(for: stats.rate))
                            Text(Fmt.percent(stats.rate)).font(.subheadline.bold().monospacedDigit())
                        }
                        .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(stats.taken) taken · \(stats.missed) missed · \(stats.skipped) skipped").font(.subheadline)
                            Text("Adherence = doses taken ÷ doses due").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Supply") {
                if let stock = medication.stockCount {
                    LabeledContent("On hand", value: Fmt.dose(stock, unit: medication.unit))
                    if let days = medication.daysOfSupply {
                        LabeledContent("Lasts about", value: "\(Int(days)) day\(Int(days) == 1 ? "" : "s")")
                    }
                    LabeledContent("Remind me at", value: "\(medication.refillThresholdDays) days left")
                    Button { showRefill = true } label: { Label("I refilled", systemImage: "plus.circle") }
                } else {
                    Text("Not tracking stock").foregroundStyle(.secondary)
                    Button("Track how many I have") { editing = true }
                }
            }

            if !medication.instructions.isEmpty || !medication.doctor.isEmpty {
                Section("Notes") {
                    if !medication.instructions.isEmpty { Text(medication.instructions) }
                    if !medication.doctor.isEmpty { LabeledContent("Prescribed by", value: medication.doctor) }
                }
            }

            if let p = medication.prescription {
                Section("Prescription") {
                    NavigationLink { PrescriptionDetailView(prescription: p) } label: { PrescriptionRow(prescription: p) }
                }
            }

            Section {
                Button(medication.isPaused ? "Resume reminders" : "Pause reminders") {
                    medication.isPaused.toggle()
                    DataStore.save()
                    NotificationService.shared.requestReschedule()
                }
                if medication.schedule.endDate == nil || !medication.schedule.hasEnded() {
                    Button("Finish course today") {
                        var s = medication.schedule
                        s.endDate = Calendar.current.startOfDay(for: .now)
                        medication.schedule = s
                        DataStore.save()
                        NotificationService.shared.requestReschedule()
                    }
                }
                Button("Delete medicine", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Edit") { editing = true } }
        .sheet(isPresented: $editing) {
            NavigationStack { MedicationEditorView(medication: medication) }
        }
        .sheet(isPresented: $showRefill) { refillSheet.presentationDetents([.height(280)]) }
        .fullScreenCover(isPresented: $showPhoto) {
            if let data = medication.photoData, let image = UIImage(data: data) { ZoomableImageView(image: image) }
        }
        .confirmationDialog("Delete \(medication.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete medicine and its history", role: .destructive) {
                dismiss()
                DoseActions.delete(medication)
            }
        } message: {
            Text("To keep its history, pause it or finish the course instead.")
        }
        .task(id: medication.scheduleData) { loadStats() }
    }

    private var s_isTimed: Bool { medication.schedule.isTimed }

    private var refillSheet: some View {
        NavigationStack {
            Form {
                Stepper(value: $refillAmount, in: 1...1000, step: medication.type.isCountable ? 1 : 10) {
                    Text("Add \(Fmt.dose(refillAmount, unit: medication.unit))")
                }
                Text("New total: \(Fmt.dose((medication.stockCount ?? 0) + refillAmount, unit: medication.unit))").foregroundStyle(.secondary)
            }
            .navigationTitle("Refill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showRefill = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        medication.stockCount = (medication.stockCount ?? 0) + refillAmount
                        medication.lastRefillAlert = nil
                        DataStore.save()
                        showRefill = false
                    }
                }
            }
        }
    }

    private func loadStats() {
        let to = Date.now
        let from = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: to)) ?? to
        let logs = DosePlanner.logIndex(DataStore.logs(from: from, to: to.addingTimeInterval(86400)))
        stats = DosePlanner.stats(for: [medication], from: from, to: to, logs: logs)
    }

    private func color(for rate: Double?) -> Color {
        guard let rate else { return .secondary }
        return rate >= 0.9 ? .doseTaken : rate >= 0.6 ? .doseDue : .doseMissed
    }
}
