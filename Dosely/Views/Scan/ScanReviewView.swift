import SwiftData
import SwiftUI

/// Mandatory review: parsed fields beside the original image, low-confidence fields highlighted,
/// and Save stays disabled until every flagged medicine is confirmed.
struct ScanReviewView: View {
    let image: UIImage
    let output: ScanPipeline.Output
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @AppStorage(Prefs.activeProfileID) private var activeID = ""

    @State private var drafts: [DraftMedication]
    @State private var doctor: String
    @State private var date: Date
    @State private var editing: DraftMedication?
    @State private var showImage = false
    @State private var keepImage = true

    init(image: UIImage, output: ScanPipeline.Output, onSaved: @escaping () -> Void) {
        self.image = image
        self.output = output
        self.onSaved = onSaved
        _drafts = State(initialValue: output.parsed.medications.enumerated().map { DraftMedication(parsed: $1, doctor: output.parsed.doctor, index: $0) })
        _doctor = State(initialValue: output.parsed.doctor)
        _date = State(initialValue: output.parsed.date ?? .now)
    }

    private var profile: Profile? { ActiveProfile.resolve(profiles, id: activeID) }
    private var meals: MealTimes { profile?.mealTimes ?? MealTimes() }
    private var included: [DraftMedication] { drafts.filter(\.include) }
    private var unconfirmed: Int { included.filter { !$0.confirmed }.count }
    private var canSave: Bool { !included.isEmpty && unconfirmed == 0 && included.allSatisfy(\.isValid) }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Button { showImage = true } label: {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 84, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2.bold()).padding(5)
                                    .background(.ultraThinMaterial, in: Circle()).padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View original prescription")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summaryTitle).font(.headline)
                        Text("Compare each medicine with your prescription. Tap a medicine to fix anything.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Label(output.usedAI ? "Read with on-device Apple Intelligence" : "Read with on-device text recognition",
                              systemImage: output.usedAI ? "sparkles" : "text.viewfinder")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Prescription") {
                TextField("Doctor", text: $doctor).textInputAutocapitalization(.words)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if let profile, profiles.count > 1 {
                    LabeledContent("For", value: profile.name)
                }
            }

            Section {
                ForEach(drafts) { draft in
                    ReviewCard(draft: draft, meals: meals, onEdit: { editing = draft })
                }
                .onDelete { drafts.remove(atOffsets: $0) }
                Button {
                    let d = DraftMedication()
                    d.doctor = doctor
                    d.confirmed = false
                    drafts.append(d)
                    editing = d
                } label: {
                    Label("Add a medicine we missed", systemImage: "plus.circle")
                }
            } header: {
                Text("Medicines (\(included.count))")
            } footer: {
                if unconfirmed > 0 {
                    Text("\(unconfirmed) medicine\(unconfirmed == 1 ? " needs" : "s need") checking before you can save.")
                        .foregroundStyle(Color.doseDue)
                }
            }

            if !output.lines.isEmpty {
                Section {
                    DisclosureGroup("Text we read") {
                        Text(output.lines.joined(separator: "\n"))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Toggle("Keep prescription photo", isOn: $keepImage)
            } footer: {
                Text("Stored only on this iPhone so you can refer back to it. Dosely does not give medical advice — always follow your doctor's instructions.")
            }
        }
        .navigationTitle("Check your medicines")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text(canSave ? "Save \(included.count) medicine\(included.count == 1 ? "" : "s")" : (unconfirmed > 0 ? "Check \(unconfirmed) more" : "Add a medicine to save"))
            }
            .primaryButton()
            .disabled(!canSave)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(item: $editing) { draft in
            NavigationStack {
                MedicationEditorView(draft: draft) {}
            }
        }
        .fullScreenCover(isPresented: $showImage) { ZoomableImageView(image: image) }
    }

    private var summaryTitle: String {
        switch drafts.count {
        case 0: "No medicines found"
        case 1: "We found 1 medicine"
        default: "We found \(drafts.count) medicines"
        }
    }

    private func save() {
        let prescription = Prescription(source: "scan")
        prescription.doctor = doctor
        prescription.date = date
        prescription.rawText = output.lines.joined(separator: "\n")
        if keepImage { prescription.imageData = image.storageJPEG() }
        prescription.profile = profile
        context.insert(prescription)
        for draft in included {
            let med = Medication(name: draft.name)
            if draft.doctor.isEmpty { draft.doctor = doctor }
            draft.apply(to: med)
            med.profile = profile
            med.prescription = prescription
            context.insert(med)
        }
        try? context.save()
        NotificationService.shared.requestReschedule()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved()
    }
}

private struct ReviewCard: View {
    @Bindable var draft: DraftMedication
    let meals: MealTimes
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                PillIconView(draft, size: 40)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(draft.name.isEmpty ? "Unnamed medicine" : draft.name)
                            .font(.headline)
                            .highlighted(draft.nameConfidence == .low && !draft.confirmed)
                        if !draft.strength.isEmpty {
                            Text(draft.strength).font(.subheadline)
                                .highlighted(draft.strengthConfidence == .low && !draft.confirmed)
                        }
                    }
                    if !draft.genericName.isEmpty {
                        Text(draft.genericName).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(scheduleLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .highlighted(draft.frequencyConfidence == .low && !draft.confirmed)
                }
                Spacer(minLength: 0)
                Toggle("Include", isOn: $draft.include).labelsHidden()
            }

            if draft.include && !draft.notes.isEmpty && !draft.confirmed {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Color.doseDue)
                    }
                }
            }
            if !draft.sourceLine.isEmpty {
                Text("“\(draft.sourceLine.replacingOccurrences(of: "\n", with: " "))”")
                    .font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(2)
            }

            if draft.include {
                HStack {
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(.bordered)
                    Spacer()
                    if draft.confirmed {
                        Label("Checked", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.doseTaken)
                            .onTapGesture { draft.confirmed = false }
                    } else {
                        Button {
                            withAnimation { draft.confirmed = true }
                        } label: {
                            Label("Looks right", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.isValid)
                    }
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(.vertical, 6)
        .opacity(draft.include ? 1 : 0.5)
    }

    private var scheduleLine: String {
        let s = draft.schedule
        var parts = [Fmt.dose(s.times.first?.amount ?? 1, unit: draft.unit), s.frequencyText(meals)]
        if s.isTimed { parts.append(s.timesText(meals)) }
        if s.foodTiming != .any { parts.append(s.foodTiming.label.lowercased()) }
        parts.append(s.durationDays.map { "\($0) days" } ?? "ongoing")
        return parts.joined(separator: " · ")
    }
}

private extension View {
    func highlighted(_ on: Bool) -> some View {
        self.padding(.horizontal, on ? 4 : 0)
            .background(on ? Color.doseDue.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
}
