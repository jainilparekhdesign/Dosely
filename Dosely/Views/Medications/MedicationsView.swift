import SwiftData
import SwiftUI

struct MedicationsView: View {
    @Environment(Router.self) private var router
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \Medication.name) private var allMeds: [Medication]
    @Query(sort: \Prescription.createdAt, order: .reverse) private var allPrescriptions: [Prescription]
    @AppStorage(Prefs.activeProfileID) private var activeID = ""
    @State private var search = ""

    private var profile: Profile? { ActiveProfile.resolve(profiles, id: activeID) }

    private var meds: [Medication] {
        allMeds.filter { $0.profile?.id == profile?.id }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.genericName.localizedCaseInsensitiveContains(search) }
    }

    private var prescriptions: [Prescription] { allPrescriptions.filter { $0.profile?.id == profile?.id } }

    var body: some View {
        NavigationStack {
            List {
                let scheduled = meds.filter { $0.isActive && $0.schedule.isTimed }
                let asNeeded = meds.filter { $0.isActive && !$0.schedule.isTimed }
                let inactive = meds.filter { !$0.isActive }

                if meds.isEmpty && search.isEmpty {
                    Section { EmptyMedsView().listRowBackground(Color.clear) }
                }
                if !scheduled.isEmpty {
                    Section("Scheduled") { ForEach(scheduled) { MedicationRow(med: $0) } }
                }
                if !asNeeded.isEmpty {
                    Section("As needed") { ForEach(asNeeded) { MedicationRow(med: $0) } }
                }
                if !inactive.isEmpty {
                    Section("Paused & finished") { ForEach(inactive) { MedicationRow(med: $0) } }
                }
                if !prescriptions.isEmpty && search.isEmpty {
                    Section("Prescriptions") {
                        ForEach(prescriptions) { p in
                            NavigationLink(value: p) { PrescriptionRow(prescription: p) }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search medicines")
            .navigationTitle("Medicines")
            .navigationDestination(for: Medication.self) { MedicationDetailView(medication: $0) }
            .navigationDestination(for: Prescription.self) { PrescriptionDetailView(prescription: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileSwitcher() }
                ToolbarItem(placement: .topBarTrailing) { AddMenu() }
            }
        }
    }
}

struct MedicationRow: View {
    let med: Medication

    var body: some View {
        NavigationLink(value: med) {
            HStack(spacing: 14) {
                MedicationThumb(med: med, size: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.displayName).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    if med.needsRefill {
                        Label("Low stock · \(Fmt.dose(med.stockCount ?? 0, unit: med.unit)) left", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.doseDue)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var subtitle: String {
        if med.isPaused { return "Paused" }
        let s = med.schedule
        var parts = [s.frequencyText(med.mealTimes)]
        if s.isTimed { parts.append(s.timesText(med.mealTimes)) }
        if let d = s.durationText() { parts.append(d) }
        return parts.joined(separator: " · ")
    }
}

struct PrescriptionRow: View {
    let prescription: Prescription

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = prescription.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 56)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(prescription.doctor.isEmpty ? "Prescription" : prescription.doctor).font(.headline)
                Text((prescription.date ?? prescription.createdAt).formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("\(prescription.medications?.count ?? 0) medicine\(prescription.medications?.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PrescriptionDetailView: View {
    @Bindable var prescription: Prescription
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showImage = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let data = prescription.imageData, let image = UIImage(data: data) {
                Section {
                    Button { showImage = true } label: {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    Button("Delete photo", role: .destructive) { prescription.imageData = nil; try? context.save() }
                } footer: {
                    Text("Tap to zoom. Deleting the photo keeps your medicines and history.")
                }
            }
            Section("Details") {
                TextField("Doctor", text: $prescription.doctor)
                DatePicker("Date", selection: Binding(get: { prescription.date ?? prescription.createdAt }, set: { prescription.date = $0 }), displayedComponents: .date)
                LabeledContent("Added", value: prescription.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Source", value: prescription.source == "scan" ? "Scanned" : "Manual")
            }
            if let meds = prescription.medications, !meds.isEmpty {
                Section("Medicines") { ForEach(meds) { MedicationRow(med: $0) } }
            }
            if !prescription.rawText.isEmpty {
                Section("Recognised text") {
                    Text(prescription.rawText).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Section {
                Button("Delete prescription", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Medicines added from this prescription are kept.")
            }
        }
        .navigationTitle(prescription.doctor.isEmpty ? "Prescription" : prescription.doctor)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showImage) {
            if let data = prescription.imageData, let image = UIImage(data: data) { ZoomableImageView(image: image) }
        }
        .confirmationDialog("Delete this prescription?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(prescription)
                try? context.save()
                dismiss()
            }
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = max(1, min(lastScale * $0.magnification, 6)) }
                            .onEnded { _ in lastScale = scale; if scale == 1 { offset = .zero; lastOffset = .zero } }
                            .simultaneously(with: DragGesture()
                                .onChanged { v in
                                    guard scale > 1 else { return }
                                    offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset })
                    )
                    .onTapGesture(count: 2) {
                        withAnimation { scale = scale > 1 ? 1 : 2.5; lastScale = scale; offset = .zero; lastOffset = .zero }
                    }
            }
            .background(Color.black)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
