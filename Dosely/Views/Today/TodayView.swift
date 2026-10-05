import SwiftData
import SwiftUI
import UserNotifications

struct TodayView: View {
    @Environment(Router.self) private var router
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \Medication.name) private var allMeds: [Medication]
    @AppStorage(Prefs.activeProfileID) private var activeID = ""
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var profile: Profile? { ActiveProfile.resolve(profiles, id: activeID) }
    private var meds: [Medication] { allMeds.filter { $0.profile?.id == profile?.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WeekStrip(selected: $selectedDay)
                    if meds.isEmpty {
                        EmptyMedsView()
                    } else {
                        TodayDoseList(day: selectedDay, meds: meds)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: Medication.self) { MedicationDetailView(medication: $0) }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileSwitcher() }
                ToolbarItem(placement: .topBarTrailing) { AddMenu() }
            }
            .onChange(of: router.tab) { _, tab in
                if tab == .today { selectedDay = Calendar.current.startOfDay(for: .now) }
            }
        }
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return profile.map { profiles.count > 1 ? "\($0.name) · Today" : "Today" } ?? "Today" }
        if cal.isDateInYesterday(selectedDay) { return "Yesterday" }
        if cal.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

struct AddMenu: View {
    @Environment(Router.self) private var router

    var body: some View {
        Menu {
            Button { router.showScan = true } label: { Label("Scan prescription", systemImage: "doc.viewfinder") }
            Button { router.showAddMedication = true } label: { Label("Add medicine manually", systemImage: "square.and.pencil") }
        } label: {
            Image(systemName: "plus").font(.body.weight(.semibold))
        }
        .accessibilityLabel("Add medicine")
    }
}

/// Logs are queried for just the visible day.
struct TodayDoseList: View {
    let day: Date
    let meds: [Medication]
    @Query private var logs: [DoseLog]
    @State private var notificationStatus: UNAuthorizationStatus = .authorized
    @State private var logLate: PlannedDose?

    init(day: Date, meds: [Medication]) {
        self.day = day
        self.meds = meds
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _logs = Query(filter: #Predicate<DoseLog> { $0.scheduledAt >= start && $0.scheduledAt < end }, sort: \.scheduledAt)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let doses = DosePlanner.doses(for: meds, on: day, logs: DosePlanner.logIndex(logs))
            let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: now)

            VStack(alignment: .leading, spacing: 20) {
                SummaryCard(doses: doses, now: now, isFuture: isFuture)
                banners
                if doses.isEmpty && asNeededMeds.isEmpty {
                    ContentUnavailableView("Nothing scheduled", systemImage: "checkmark.seal",
                                           description: Text("No doses planned for this day."))
                        .padding(.vertical, 24)
                }
                ForEach(DayPeriod.allCases) { period in
                    let group = doses.filter { DosePlanner.period(for: $0.scheduledAt) == period }
                    if !group.isEmpty {
                        PeriodSection(period: period, doses: group, now: now, canLog: !isFuture, onLogLate: { logLate = $0 })
                    }
                }
                if !asNeededMeds.isEmpty && !isFuture {
                    AsNeededSection(meds: asNeededMeds, logs: logs.filter(\.isAsNeeded), day: day)
                }
            }
        }
        .task { notificationStatus = await NotificationService.shared.authorizationStatus() }
        .sheet(item: $logLate) { dose in
            LogTimeSheet(dose: dose)
                .presentationDetents([.medium])
        }
    }

    private var asNeededMeds: [Medication] {
        meds.filter { $0.schedule.pattern == .asNeeded && $0.isActive }
    }

    @ViewBuilder private var banners: some View {
        if notificationStatus == .denied {
            InfoBanner(icon: "bell.slash.fill", title: "Reminders are off",
                       message: "Turn on notifications so you don't miss a dose.", tint: .doseMissed,
                       actionTitle: "Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
        } else if notificationStatus == .notDetermined {
            InfoBanner(icon: "bell.badge.fill", title: "Get reminded at each dose time",
                       message: "Allow notifications to get reminders you can act on.", actionTitle: "Turn on reminders") {
                Task { _ = await NotificationService.shared.requestAuthorization(); notificationStatus = await NotificationService.shared.authorizationStatus() }
            }
        }
        ForEach(meds.filter(\.needsRefill)) { med in
            NavigationLink(value: med) {
                InfoBanner(icon: "exclamationmark.triangle.fill", title: "Refill \(med.name) soon",
                           message: "\(Fmt.dose(med.stockCount ?? 0, unit: med.unit)) left · about \(Int(med.daysOfSupply ?? 0)) days",
                           tint: .doseDue)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SummaryCard: View {
    let doses: [PlannedDose]
    let now: Date
    let isFuture: Bool

    var body: some View {
        let taken = doses.filter { $0.log?.status == .taken }.count
        let total = doses.count
        let next = doses.first { $0.log == nil && $0.scheduledAt > now.addingTimeInterval(-DosePlanner.dueWindow) }
        let missed = doses.filter { $0.status(now: now) == .missed }.count

        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: total == 0 ? 0 : Double(taken) / Double(total), lineWidth: 9)
                VStack(spacing: 0) {
                    Text("\(taken)").font(.title2.bold().monospacedDigit())
                    Text("of \(total)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(taken) of \(total) doses taken")

            VStack(alignment: .leading, spacing: 4) {
                Text(headline(taken: taken, total: total, missed: missed)).font(.headline)
                if let next, !isFuture {
                    Text("Next: \(next.medication.name) at \(Fmt.time(next.scheduledAt))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if isFuture {
                    Text("\(total) dose\(total == 1 ? "" : "s") planned").font(.subheadline).foregroundStyle(.secondary)
                }
                if missed > 0 && !isFuture {
                    Label("\(missed) missed", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Color.doseMissed)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func headline(taken: Int, total: Int, missed: Int) -> String {
        if total == 0 { return "No scheduled doses" }
        if isFuture { return "Coming up" }
        if taken == total { return "All done for the day 🎉" }
        if taken == 0 { return "Let's get started" }
        return "\(total - taken) to go"
    }
}

private struct PeriodSection: View {
    let period: DayPeriod
    let doses: [PlannedDose]
    let now: Date
    let canLog: Bool
    let onLogLate: (PlannedDose) -> Void

    var body: some View {
        let pending = doses.filter { $0.log == nil && [.due, .missed].contains($0.status(now: now)) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(period.label, systemImage: period.symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if canLog && pending.count > 1 {
                    Button {
                        withAnimation {
                            for dose in pending {
                                DoseActions.mark(.taken, medicationID: dose.medication.id, scheduledAt: dose.scheduledAt, amount: dose.amount)
                            }
                        }
                    } label: {
                        Label("Take all (\(pending.count))", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            ForEach(doses) { dose in
                DoseCard(dose: dose, now: now, canLog: canLog, onLogLate: { onLogLate(dose) })
            }
        }
    }
}

struct DoseCard: View {
    let dose: PlannedDose
    let now: Date
    var canLog = true
    var onLogLate: () -> Void = {}

    var body: some View {
        let status = dose.status(now: now)
        let med = dose.medication
        HStack(spacing: 14) {
            NavigationLink(value: med) {
                HStack(spacing: 14) {
                    MedicationThumb(med: med, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(med.name).font(.headline).lineLimit(1)
                            if med.isCritical {
                                Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(Color.doseMissed)
                                    .accessibilityLabel("Critical")
                            }
                        }
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(Fmt.time(dose.scheduledAt)).font(.subheadline.weight(.medium).monospacedDigit())
                            if status != .upcoming { StatusChip(status: status) }
                        }
                        if let log = dose.log, log.status == .taken, let at = log.actualAt,
                           abs(at.timeIntervalSince(dose.scheduledAt)) > 20 * 60 {
                            Text("Taken at \(Fmt.time(at))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if canLog { actionButton(status) }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(status == .due ? Color.doseDue.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .opacity(status == .skipped ? 0.6 : 1)
        .contextMenu { if canLog { menuItems } }
        .accessibilityElement(children: .combine)
        .accessibilityHint(canLog ? "Double-tap Take to mark this dose as taken" : "")
    }

    private var detail: String {
        var parts = [Fmt.dose(dose.amount, unit: dose.medication.unit)]
        let s = dose.medication.schedule
        let minutes = Fmt.minutes(from: dose.scheduledAt)
        if let time = s.times.first(where: { $0.anchor != nil && $0.resolvedMinutes(dose.medication.mealTimes) == minutes }) {
            parts.append(time.label(dose.medication.mealTimes).lowercased())
        } else if s.foodTiming != .any {
            parts.append(s.foodTiming.label.lowercased())
        }
        if !dose.medication.strength.isEmpty { parts.insert(dose.medication.strength, at: 0) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func actionButton(_ status: DisplayStatus) -> some View {
        if status == .taken || status == .skipped {
            Menu {
                menuItems
            } label: {
                Image(systemName: status == .taken ? "checkmark.circle.fill" : "forward.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(status == .taken ? Color.doseTaken : Color.doseSkipped)
                    .symbolEffect(.bounce, value: status)
            }
            .accessibilityLabel(status == .taken ? "Taken. Change" : "Skipped. Change")
        } else {
            Button {
                withAnimation(.spring) {
                    DoseActions.mark(.taken, medicationID: dose.medication.id, scheduledAt: dose.scheduledAt, amount: dose.amount)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Text("Take")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(status == .missed ? Color.doseMissed : Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take \(dose.medication.name)")
        }
    }

    @ViewBuilder private var menuItems: some View {
        let id = dose.medication.id
        if dose.log?.status != .taken {
            Button { DoseActions.mark(.taken, medicationID: id, scheduledAt: dose.scheduledAt, amount: dose.amount) } label: {
                Label("Taken now", systemImage: "checkmark.circle")
            }
        }
        Button(action: onLogLate) { Label("Taken at a different time…", systemImage: "clock.arrow.circlepath") }
        if dose.log?.status != .skipped {
            Button { DoseActions.mark(.skipped, medicationID: id, scheduledAt: dose.scheduledAt, amount: dose.amount) } label: {
                Label("Skip this dose", systemImage: "forward")
            }
        }
        if dose.log != nil {
            Button(role: .destructive) { DoseActions.undo(medicationID: id, scheduledAt: dose.scheduledAt) } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
        }
    }
}

/// Log a dose with the time it was actually taken.
struct LogTimeSheet: View {
    let dose: PlannedDose
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(dose: PlannedDose) {
        self.dose = dose
        _time = State(initialValue: dose.log?.actualAt ?? min(dose.scheduledAt, .now))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MedicationThumb(med: dose.medication, size: 44)
                        VStack(alignment: .leading) {
                            Text(dose.medication.displayName).font(.headline)
                            Text("Scheduled \(Fmt.time(dose.scheduledAt))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("When did you take it?") {
                    DatePicker("Time taken", selection: $time, in: ...Date.now)
                }
            }
            .navigationTitle("Log dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        DoseActions.mark(.taken, medicationID: dose.medication.id, scheduledAt: dose.scheduledAt, amount: dose.amount, at: time)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AsNeededSection: View {
    let meds: [Medication]
    let logs: [DoseLog]
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("As needed", systemImage: "hand.raised.fill")
                .font(.headline).foregroundStyle(.secondary)
            ForEach(meds) { med in
                let taken = logs.filter { $0.medicationID == med.id }
                let max = med.schedule.maxDailyAsNeeded
                HStack(spacing: 14) {
                    MedicationThumb(med: med, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(med.displayName).font(.headline)
                        Text(taken.isEmpty ? "Not taken today" : "Taken \(taken.count)× · last \(Fmt.time(taken.map(\.scheduledAt).max() ?? .now))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let max, taken.count >= max {
                            Text("Daily limit of \(max) reached").font(.caption.weight(.semibold)).foregroundStyle(Color.doseMissed)
                        }
                    }
                    Spacer()
                    Menu {
                        Button("Log \(Fmt.dose(med.schedule.times.first?.amount ?? 1, unit: med.unit)) now") {
                            DoseActions.logAsNeeded(med, amount: med.schedule.times.first?.amount ?? 1,
                                                    at: Calendar.current.isDateInToday(day) ? .now : day.addingTimeInterval(12 * 3600))
                        }
                        if let last = taken.max(by: { $0.scheduledAt < $1.scheduledAt }) {
                            Button("Remove last entry", role: .destructive) { DoseActions.deleteAsNeeded(last) }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 36)).foregroundStyle(.tint)
                    }
                    .accessibilityLabel("Log a dose of \(med.name)")
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

struct WeekStrip: View {
    @Binding var selected: Date

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (-6...7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let isSelected = cal.isDate(day, inSameDayAs: selected)
                        Button { withAnimation(.snappy) { selected = day } } label: {
                            VStack(spacing: 4) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.medium))
                                Text(day.formatted(.dateTime.day())).font(.title3.weight(.semibold).monospacedDigit())
                                Circle().fill(cal.isDateInToday(day) ? (isSelected ? Color.white : Color.accentColor) : .clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(width: 46, height: 70)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(day)
                        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(today, anchor: .center) }
            .onChange(of: selected) { _, d in withAnimation { proxy.scrollTo(d, anchor: .center) } }
        }
    }
}

struct EmptyMedsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 40)
            Text("Add your first prescription").font(.title2.bold())
            Text("Scan it and Dosely sets up every medicine, dose and time for you. You'll check everything before it's saved.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { router.showScan = true } label: {
                Label("Scan prescription", systemImage: "camera.viewfinder")
            }
            .primaryButton()
            Button("Add a medicine manually") { router.showAddMedication = true }
                .font(.body.weight(.medium))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }
}
