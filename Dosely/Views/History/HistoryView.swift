import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \Medication.name) private var allMeds: [Medication]
    @AppStorage(Prefs.activeProfileID) private var activeID = ""
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)
    @State private var showReport = false

    private var profile: Profile? { ActiveProfile.resolve(profiles, id: activeID) }
    private var meds: [Medication] { allMeds.filter { $0.profile?.id == profile?.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                MonthHistory(month: month, meds: meds, selectedDay: $selectedDay, onChangeMonth: changeMonth)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .navigationDestination(for: Medication.self) { MedicationDetailView(medication: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileSwitcher() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showReport = true } label: { Label("Report", systemImage: "square.and.arrow.up") }
                        .disabled(meds.isEmpty)
                }
            }
            .sheet(isPresented: $showReport) {
                ReportView(profile: profile, meds: meds)
            }
        }
    }

    private func changeMonth(_ delta: Int) {
        if let m = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.snappy) { month = m }
            selectedDay = nil
        }
    }
}

/// Loads logs for one month only.
private struct MonthHistory: View {
    let month: Date
    let meds: [Medication]
    @Binding var selectedDay: Date?
    let onChangeMonth: (Int) -> Void
    @Query private var logs: [DoseLog]

    init(month: Date, meds: [Medication], selectedDay: Binding<Date?>, onChangeMonth: @escaping (Int) -> Void) {
        self.month = month
        self.meds = meds
        _selectedDay = selectedDay
        self.onChangeMonth = onChangeMonth
        let start = month
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
        _logs = Query(filter: #Predicate<DoseLog> { $0.scheduledAt >= start && $0.scheduledAt < end })
    }

    var body: some View {
        let cal = Calendar.current
        let index = DosePlanner.logIndex(logs)
        let now = Date.now
        let end = cal.date(byAdding: .month, value: 1, to: month) ?? month
        let monthStats = DosePlanner.stats(for: meds, from: month, to: end, logs: index, now: now)

        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                StatTile(title: "Adherence", value: Fmt.percent(monthStats.rate), tint: tint(monthStats.rate))
                StatTile(title: "Taken", value: "\(monthStats.taken)", tint: .doseTaken)
                StatTile(title: "Missed", value: "\(monthStats.missed)", tint: monthStats.missed > 0 ? .doseMissed : .secondary)
            }

            VStack(spacing: 12) {
                HStack {
                    Button { onChangeMonth(-1) } label: { Image(systemName: "chevron.left").padding(8) }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { onChangeMonth(1) } label: { Image(systemName: "chevron.right").padding(8) }
                        .disabled(end > now)
                        .accessibilityLabel("Next month")
                }
                CalendarGrid(month: month, selected: $selectedDay) { day in
                    let doses = DosePlanner.doses(for: meds, on: day, logs: index)
                    return (DosePlanner.stats(for: doses, now: now), doses.isEmpty)
                }
                Legend()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            if let day = selectedDay {
                DayDetail(day: day, meds: meds, logs: index, asNeeded: logs.filter { $0.isAsNeeded && cal.isDate($0.scheduledAt, inSameDayAs: day) })
            }

            let timed = meds.filter { $0.schedule.isTimed }
            if !timed.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("By medicine").font(.headline)
                    ForEach(timed) { med in
                        let s = DosePlanner.stats(for: [med], from: month, to: end, logs: index, now: now)
                        if s.scheduled > 0 {
                            NavigationLink(value: med) {
                                HStack(spacing: 12) {
                                    MedicationThumb(med: med, size: 40)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(med.displayName).font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(Fmt.percent(s.rate)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(tint(s.rate))
                                        }
                                        ProgressView(value: s.rate ?? 0).tint(tint(s.rate))
                                        Text("\(s.taken) of \(s.scheduled) taken").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func tint(_ rate: Double?) -> Color {
        guard let rate else { return .secondary }
        return rate >= 0.9 ? .doseTaken : rate >= 0.6 ? .doseDue : .doseMissed
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct CalendarGrid: View {
    let month: Date
    @Binding var selected: Date?
    let stats: (Date) -> (AdherenceStats, Bool)

    var body: some View {
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekday = cal.component(.weekday, from: month)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let symbols = cal.veryShortWeekdaySymbols
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 }
        let today = cal.startOfDay(for: .now)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(order.map { "h\($0)" }, id: \.self) { key in
                Text(symbols[Int(key.dropFirst())!]).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach((0..<leading).map { "pad\($0)" }, id: \.self) { _ in Color.clear.frame(height: 40) }
            ForEach(Array(1...days), id: \.self) { d in
                let day = cal.date(byAdding: .day, value: d - 1, to: month) ?? month
                let isFuture = day > today
                let (s, empty) = isFuture ? (AdherenceStats(), true) : stats(day)
                let isSelected = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
                Button { selected = day } label: {
                    ZStack {
                        if !empty && s.scheduled > 0 {
                            ProgressRing(progress: s.rate ?? 0, lineWidth: 3.5, color: ringColor(s.rate))
                        }
                        Text("\(d)")
                            .font(.subheadline.weight(cal.isDateInToday(day) ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(isFuture ? .secondary : (cal.isDateInToday(day) ? Color.accentColor : .primary))
                    }
                    .frame(width: 38, height: 38)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibility(day: day, stats: s, empty: empty || isFuture))
            }
        }
    }

    private func ringColor(_ rate: Double?) -> Color {
        guard let rate else { return .secondary }
        return rate >= 0.999 ? .doseTaken : rate >= 0.5 ? .doseDue : .doseMissed
    }

    private func accessibility(day: Date, stats: AdherenceStats, empty: Bool) -> String {
        let date = day.formatted(date: .abbreviated, time: .omitted)
        if empty || stats.scheduled == 0 { return date }
        return "\(date): \(stats.taken) of \(stats.scheduled) taken"
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(.doseTaken, "All taken")
            item(.doseDue, "Some missed")
            item(.doseMissed, "Mostly missed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func item(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t) }
    }
}

private struct DayDetail: View {
    let day: Date
    let meds: [Medication]
    let logs: [String: DoseLog]
    let asNeeded: [DoseLog]
    @State private var logLate: PlannedDose?

    var body: some View {
        let doses = DosePlanner.doses(for: meds, on: day, logs: logs)
        let canLog = Calendar.current.startOfDay(for: day) <= Calendar.current.startOfDay(for: .now)
        VStack(alignment: .leading, spacing: 10) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
            if doses.isEmpty && asNeeded.isEmpty {
                Text("No doses scheduled.").foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(doses) { dose in
                DoseCard(dose: dose, now: .now, canLog: canLog, onLogLate: { logLate = dose })
            }
            ForEach(asNeeded) { log in
                if let med = meds.first(where: { $0.id == log.medicationID }) {
                    HStack(spacing: 12) {
                        MedicationThumb(med: med, size: 40)
                        VStack(alignment: .leading) {
                            Text(med.displayName).font(.subheadline.weight(.semibold))
                            Text("As needed · \(Fmt.dose(log.amount, unit: med.unit)) at \(Fmt.time(log.scheduledAt))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .sheet(item: $logLate) { LogTimeSheet(dose: $0).presentationDetents([.medium]) }
    }
}
