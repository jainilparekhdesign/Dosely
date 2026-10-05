import PhotosUI
import SwiftData
import SwiftUI

/// Add/edit form. In "draft" mode (scan review) it edits the draft only; otherwise it saves to the database.
struct MedicationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @AppStorage(Prefs.activeProfileID) private var activeID = ""

    private let medication: Medication?
    private let isDraftMode: Bool
    private let onDraftDone: (() -> Void)?
    @State private var draft: DraftMedication
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var endMode: EndMode

    enum EndMode: String, CaseIterable, Identifiable {
        case never, days, date
        var id: String { rawValue }
        var label: String {
            switch self {
            case .never: "Ongoing"
            case .days: "After a number of days"
            case .date: "On a date"
            }
        }
    }

    init(medication: Medication?) {
        self.medication = medication
        self.isDraftMode = false
        self.onDraftDone = nil
        let d = medication.map(DraftMedication.init(from:)) ?? DraftMedication()
        _draft = State(initialValue: d)
        _endMode = State(initialValue: d.schedule.endDate == nil ? .never : .days)
    }

    init(draft: DraftMedication, onDone: @escaping () -> Void) {
        self.medication = nil
        self.isDraftMode = true
        self.onDraftDone = onDone
        _draft = State(initialValue: draft)
        _endMode = State(initialValue: draft.schedule.endDate == nil ? .never : .days)
    }

    private var meals: MealTimes { medication?.mealTimes ?? ActiveProfile.resolve(profiles, id: activeID)?.mealTimes ?? MealTimes() }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    PillIconView(draft, size: 60)
                        .frame(width: 72, height: 72)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18))
                    VStack(spacing: 8) {
                        TextField("Medicine name", text: $draft.name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        TextField("Strength, e.g. 500 mg", text: $draft.strength)
                            .autocorrectionDisabled()
                    }
                }
                if !draft.genericName.isEmpty {
                    LabeledContent("Generic", value: draft.genericName)
                }
            }

            appearanceSection
            scheduleSection
            durationSection

            Section {
                Toggle(isOn: $draft.tracksStock.animation()) { Label("Track supply", systemImage: "shippingbox") }
                if draft.tracksStock {
                    Stepper(value: $draft.stockCount, in: 0...2000, step: draft.type.isCountable ? 1 : 10) {
                        LabeledContent("On hand", value: Fmt.dose(draft.stockCount, unit: draft.unit))
                    }
                    Stepper(value: $draft.refillThresholdDays, in: 1...30) {
                        LabeledContent("Refill alert", value: "\(draft.refillThresholdDays) days left")
                    }
                }
            } header: {
                Text("Refills")
            } footer: {
                if draft.tracksStock { Text("Dosely counts down as you log doses and warns you before you run out.") }
            }

            Section {
                Toggle(isOn: $draft.isCritical) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Critical medicine")
                        Text("Reminders break through Focus modes").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Notes") {
                TextField("Instructions (e.g. with a full glass of water)", text: $draft.instructions, axis: .vertical)
                    .lineLimit(1...4)
                TextField("Prescribing doctor", text: $draft.doctor)
                    .textInputAutocapitalization(.words)
            }
        }
        .navigationTitle(isDraftMode ? "Check medicine" : (medication == nil ? "New medicine" : "Edit medicine"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isDraftMode {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isDraftMode ? "Done" : "Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid)
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    draft.photoData = image.storageJPEG(maxDimension: 800)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in draft.photoData = image.storageJPEG(maxDimension: 800) }
                .ignoresSafeArea()
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Type & look") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MedType.allCases) { type in
                        Button {
                            withAnimation(.snappy) {
                                let oldDefault = draft.type.defaultUnit
                                draft.type = type
                                if draft.unit == oldDefault || draft.unit.isEmpty { draft.unit = type.defaultUnit }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                PillIconView(type: type, shape: .round, colorHex: draft.type == type ? draft.colorHex : "#FFFFFF",
                                             secondaryHex: draft.secondaryColorHex, size: 34)
                                Text(type.label).font(.caption2.weight(.medium))
                            }
                            .frame(width: 70, height: 70)
                            .background(draft.type == type ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(draft.type == type ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(type.label)
                        .accessibilityAddTraits(draft.type == type ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            if draft.type == .tablet {
                Picker("Shape", selection: $draft.shape) {
                    ForEach(PillShape.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            ColorRow(title: draft.type == .capsule ? "Colour (left half)" : "Colour", selection: $draft.colorHex)
            if draft.type == .capsule {
                ColorRow(title: "Colour (right half)", selection: $draft.secondaryColorHex)
            }

            HStack {
                Label("Photo of pill or box", systemImage: "camera")
                Spacer()
                if let data = draft.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from library", systemImage: "photo") }
                    if draft.photoData != nil {
                        Button("Remove photo", role: .destructive) { draft.photoData = nil }
                    }
                } label: {
                    Text(draft.photoData == nil ? "Add" : "Change")
                }
            }
        }
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        Section {
            Picker("How often", selection: $draft.schedule.pattern) {
                ForEach(SchedulePattern.allCases) { Text($0.label).tag($0) }
            }

            switch draft.schedule.pattern {
            case .daily, .weekdays, .everyXDays:
                if draft.schedule.pattern == .weekdays { WeekdayPicker(selection: $draft.schedule.weekdays) }
                if draft.schedule.pattern == .everyXDays {
                    Stepper(value: $draft.schedule.dayInterval, in: 2...30) {
                        LabeledContent("Every", value: "\(draft.schedule.dayInterval) days")
                    }
                }
                presets
                ForEach($draft.schedule.times) { $time in
                    DoseTimeRow(time: $time, unit: draft.unit, meals: meals)
                }
                .onDelete { draft.schedule.times.remove(atOffsets: $0) }
                Button {
                    let last = draft.schedule.times.map { $0.resolvedMinutes(meals) }.max() ?? 8 * 60
                    draft.schedule.times.append(DoseTime(minutes: min(last + 4 * 60, 23 * 60), amount: draft.schedule.times.last?.amount ?? 1))
                } label: {
                    Label("Add a time", systemImage: "plus.circle")
                }
            case .everyXHours:
                Stepper(value: $draft.schedule.intervalHours, in: 1...24) {
                    LabeledContent("Every", value: "\(draft.schedule.intervalHours) hours")
                }
                if draft.schedule.times.isEmpty { Color.clear.onAppear { draft.schedule.times = [DoseTime()] } }
                if !draft.schedule.times.isEmpty {
                    DatePicker("First dose", selection: Binding(
                        get: { Fmt.date(fromMinutes: draft.schedule.times[0].resolvedMinutes(meals)) },
                        set: { draft.schedule.times[0].minutes = Fmt.minutes(from: $0); draft.schedule.times[0].anchor = nil }
                    ), displayedComponents: .hourAndMinute)
                    AmountStepper(amount: $draft.schedule.times[0].amount, unit: draft.unit)
                    Text("Doses at " + intervalPreview).font(.footnote).foregroundStyle(.secondary)
                }
            case .asNeeded:
                if !draft.schedule.times.isEmpty {
                    AmountStepper(amount: $draft.schedule.times[0].amount, unit: draft.unit)
                }
                Stepper(value: Binding(get: { draft.schedule.maxDailyAsNeeded ?? 0 }, set: { draft.schedule.maxDailyAsNeeded = $0 == 0 ? nil : $0 }), in: 0...12) {
                    LabeledContent("Max per day", value: draft.schedule.maxDailyAsNeeded.map(String.init) ?? "No limit")
                }
            }

            Picker("Food", selection: $draft.schedule.foodTiming) {
                ForEach(FoodTiming.allCases) { Text($0.label).tag($0) }
            }
            if draft.type != .tablet && draft.type != .capsule {
                LabeledContent("Dose unit") {
                    TextField("unit", text: $draft.unit).multilineTextAlignment(.trailing).autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            if draft.schedule.pattern == .daily || draft.schedule.pattern == .weekdays || draft.schedule.pattern == .everyXDays {
                Text("Meal-based times follow your meal times in Settings. You can set a different amount for each time.")
            }
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(Array(zip(["1×", "2×", "3×", "4×"], [[MealAnchor.breakfast], [.breakfast, .dinner], [.breakfast, .lunch, .dinner], [.breakfast, .lunch, .dinner, .bedtime]])), id: \.0) { label, anchors in
                Button(label) {
                    let amount = draft.schedule.times.first?.amount ?? 1
                    let relation = relationForFood
                    withAnimation { draft.schedule.times = anchors.map { DoseTime.meal($0, relation, amount: amount) } }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(label.dropLast()) times a day")
            }
        }
    }

    private var relationForFood: MealRelation {
        switch draft.schedule.foodTiming {
        case .before, .emptyStomach: .before
        case .after: .after
        case .with: .with
        case .any: .at
        }
    }

    private var intervalPreview: String {
        let occ = ScheduleEngine.occurrences(of: draft.schedule, on: max(draft.schedule.startDate, .now), meals: meals)
        return occ.map { Fmt.time($0.date) }.joined(separator: ", ")
    }

    // MARK: Duration

    private var durationSection: some View {
        Section {
            DatePicker("Start", selection: Binding(
                get: { draft.schedule.startDate },
                set: { newStart in
                    let days = draft.schedule.durationDays
                    draft.schedule.startDate = Calendar.current.startOfDay(for: newStart)
                    if endMode == .days { draft.schedule.setDuration(days: days) }
                }
            ), displayedComponents: .date)
            Picker("Ends", selection: $endMode) {
                ForEach(EndMode.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: endMode) { _, mode in
                switch mode {
                case .never: draft.schedule.endDate = nil
                case .days, .date: if draft.schedule.endDate == nil { draft.schedule.setDuration(days: 7) }
                }
            }
            if endMode == .days {
                Stepper(value: Binding(get: { draft.schedule.durationDays ?? 7 }, set: { draft.schedule.setDuration(days: $0) }), in: 1...365) {
                    LabeledContent("For", value: "\(draft.schedule.durationDays ?? 7) days")
                }
            }
            if endMode == .date {
                DatePicker("Last day", selection: Binding(
                    get: { draft.schedule.endDate ?? .now },
                    set: { draft.schedule.endDate = Calendar.current.startOfDay(for: $0) }
                ), in: draft.schedule.startDate..., displayedComponents: .date)
            }
        } header: {
            Text("Duration")
        } footer: {
            if let end = draft.schedule.endDate {
                Text("The course ends automatically after \(end.formatted(date: .long, time: .omitted)).")
            }
        }
    }

    // MARK: Save

    private func save() {
        draft.schedule.times.sort { $0.resolvedMinutes(meals) < $1.resolvedMinutes(meals) }
        if isDraftMode {
            draft.confirmed = true
            onDraftDone?()
            dismiss()
            return
        }
        let med = medication ?? Medication(name: draft.name)
        draft.apply(to: med)
        if medication == nil {
            med.profile = ActiveProfile.resolve(profiles, id: activeID)
            context.insert(med)
        }
        try? context.save()
        NotificationService.shared.requestReschedule()
        dismiss()
    }
}

// MARK: - Pieces

private struct DoseTimeRow: View {
    @Binding var time: DoseTime
    let unit: String
    let meals: MealTimes

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button { time.anchor = nil; time.minutes = time.resolvedMinutes(meals) } label: { Label("Specific time", systemImage: "clock") }
                    ForEach(MealAnchor.allCases) { anchor in
                        if anchor == .bedtime {
                            Button("At bedtime") { time.anchor = .bedtime; time.relation = .at }
                        } else {
                            Menu(anchor.label) {
                                ForEach(MealRelation.allCases) { rel in
                                    Button(rel == .at ? "At \(anchor.rawValue) time" : "\(rel.label) \(anchor.rawValue)") {
                                        time.anchor = anchor
                                        time.relation = rel
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(time.anchor == nil ? "Specific time" : time.label(meals))
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .font(.subheadline.weight(.medium))
                }
                Spacer()
                if time.anchor == nil {
                    DatePicker("Time", selection: Binding(
                        get: { Fmt.date(fromMinutes: time.minutes) },
                        set: { time.minutes = Fmt.minutes(from: $0) }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                } else {
                    Text(Fmt.time(minutes: time.resolvedMinutes(meals))).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            AmountStepper(amount: $time.amount, unit: unit)
        }
        .padding(.vertical, 2)
    }
}

struct AmountStepper: View {
    @Binding var amount: Double
    let unit: String

    var body: some View {
        let isVolume = ["ml", "drop", "unit", "units"].contains(unit)
        Stepper(value: $amount, in: isVolume ? 1...200 : 0.25...20, step: isVolume ? 1 : 0.5) {
            Text(Fmt.dose(amount, unit: unit)).font(.subheadline)
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: [Int]

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { if selection.count > 1 { selection.removeAll { $0 == day } } } else { selection.append(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

private struct ColorRow: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(DraftMedication.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selection == hex ? 3 : 0).padding(-4))
                        .frame(height: 32)
                        .onTapGesture { selection = hex }
                        .accessibilityLabel("Colour \(hex)")
                        .accessibilityAddTraits(selection == hex ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(4)
        }
    }
}

/// Camera capture for pill photos.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
