import LocalAuthentication
import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var prescriptions: [Prescription]
    @AppStorage(Prefs.activeProfileID) private var activeID = ""
    @AppStorage(Prefs.followUpEnabled) private var followUpEnabled = true
    @AppStorage(Prefs.followUpMinutes) private var followUpMinutes = 30
    @AppStorage(Prefs.quietHoursEnabled) private var quietEnabled = false
    @AppStorage(Prefs.quietStart) private var quietStart = 23 * 60
    @AppStorage(Prefs.quietEnd) private var quietEnd = 7 * 60
    @AppStorage(Prefs.useOnDeviceAI) private var useAI = true
    @AppStorage(Prefs.verifyWithRxNorm) private var verifyOnline = false
    @AppStorage(Prefs.appLock) private var appLock = false
    @AppStorage(Prefs.onboarded) private var onboarded = true

    @State private var confirmDeleteImages = false
    @State private var confirmDeleteAll = false
    @State private var testSent = false

    private var profile: Profile? { ActiveProfile.resolve(profiles, id: activeID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(profiles) { p in
                        NavigationLink { ProfileEditorView(profile: p) } label: {
                            HStack(spacing: 12) {
                                ProfileAvatar(profile: p, size: 36)
                                VStack(alignment: .leading) {
                                    Text(p.name).font(.headline)
                                    Text(p.isPrimary ? "You" : (p.relationship.isEmpty ? "Family member" : p.relationship))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.id == profile?.id { Text("Viewing").font(.caption).foregroundStyle(.tint) }
                            }
                        }
                    }
                    NavigationLink { ProfileEditorView(profile: nil) } label: {
                        Label("Add someone you care for", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Profiles")
                } footer: {
                    Text("Manage medicines for a parent or child in their own profile, with their own meal times and reminders.")
                }

                Section {
                    Toggle("Follow-up if I don't respond", isOn: $followUpEnabled)
                    if followUpEnabled {
                        Picker("Follow up after", selection: $followUpMinutes) {
                            ForEach([15, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                    Toggle("Quiet hours for follow-ups", isOn: $quietEnabled)
                    if quietEnabled {
                        DatePicker("From", selection: minutesBinding($quietStart), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: minutesBinding($quietEnd), displayedComponents: .hourAndMinute)
                    }
                    Button(testSent ? "Test reminder sent — check in 5 seconds" : "Send a test reminder") { sendTest() }
                        .disabled(testSent)
                    Button("Notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Dose reminders always fire. Quiet hours only silence follow-up nudges.")
                }
                .onChange(of: followUpEnabled) { NotificationService.shared.requestReschedule() }
                .onChange(of: followUpMinutes) { NotificationService.shared.requestReschedule() }
                .onChange(of: quietEnabled) { NotificationService.shared.requestReschedule() }

                Section {
                    Toggle(isOn: $useAI) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Apple Intelligence")
                            Text(AIExtractor.isAvailable ? "Better at messy and handwritten prescriptions. Runs on-device." : "Not available on this iPhone — standard reading is used.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!AIExtractor.isAvailable)
                    Toggle(isOn: $verifyOnline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check names with RxNorm")
                            Text("Sends only medicine names (never images) to the U.S. National Library of Medicine to confirm unfamiliar names.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Scanning")
                }

                Section {
                    Toggle("Lock with Face ID", isOn: $appLock)
                        .onChange(of: appLock) { _, on in if on { verifyLock() } }
                    Button("Delete all prescription photos", role: .destructive) { confirmDeleteImages = true }
                        .disabled(prescriptions.allSatisfy { $0.imageData == nil })
                    Button("Delete all my data", role: .destructive) { confirmDeleteAll = true }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Everything is stored only on this iPhone and encrypted by iOS. Dosely has no account, sells no data and shows no ads.")
                }

                Section("About") {
                    NavigationLink("Medical disclaimer") { DisclaimerView() }
                    NavigationLink("Data sources & credits") { CreditsView() }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all prescription photos?", isPresented: $confirmDeleteImages, titleVisibility: .visible) {
                Button("Delete photos", role: .destructive) {
                    for p in prescriptions { p.imageData = nil }
                    try? context.save()
                }
            } message: {
                Text("Your medicines and history are kept.")
            }
            .confirmationDialog("Delete everything?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive, action: deleteAll)
            } message: {
                Text("This removes all profiles, medicines, prescriptions and history from this iPhone. It can't be undone.")
            }
        }
    }

    private func minutesBinding(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: { Fmt.date(fromMinutes: value.wrappedValue) }, set: {
            value.wrappedValue = Fmt.minutes(from: $0)
            NotificationService.shared.requestReschedule()
        })
    }

    private func verifyLock() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            appLock = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on app lock") { ok, _ in
            DispatchQueue.main.async { if !ok { appLock = false } }
        }
    }

    private func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Test reminder"
        content.body = "Reminders are working. Tap and hold to see Taken, Snooze and Skip."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test|\(UUID())", content: content,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
        testSent = true
        Task {
            try? await Task.sleep(for: .seconds(6))
            testSent = false
        }
    }

    private func deleteAll() {
        try? context.delete(model: DoseLog.self)
        try? context.delete(model: Medication.self)
        try? context.delete(model: Prescription.self)
        try? context.delete(model: Profile.self)
        try? context.save()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        activeID = ""
        onboarded = false
    }
}

struct ProfileEditorView: View {
    let profile: Profile?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.activeProfileID) private var activeID = ""
    @State private var name = ""
    @State private var relationship = ""
    @State private var colorHex = "#E5534B"
    @State private var meals = MealTimes()
    @State private var confirmDelete = false

    private let colors = ["#008F8F", "#3D7BF0", "#9B6BDF", "#E5534B", "#F29B38", "#3DBE7A", "#F28BB5", "#8D6E63"]

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Text(initials).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(Color(hex: colorHex), in: Circle())
                    Spacer()
                }
                .listRowBackground(Color.clear)
                TextField("Name", text: $name).textInputAutocapitalization(.words)
                if profile?.isPrimary != true {
                    TextField("Relationship (e.g. Mother, Son)", text: $relationship).textInputAutocapitalization(.words)
                }
                HStack {
                    ForEach(colors, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: colorHex == hex ? 2.5 : 0).padding(-3))
                            .onTapGesture { colorHex = hex }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Section {
                MealTimesEditor(meals: $meals).listRowInsets(EdgeInsets())
            } header: {
                Text("Meal times")
            } footer: {
                Text("Doses like “after breakfast” are timed 30 minutes after these.")
            }
            if let profile {
                Section {
                    Button(profile.id.uuidString == activeID ? "Currently viewing" : "View \(profile.name)'s medicines") {
                        activeID = profile.id.uuidString
                    }
                    .disabled(profile.id.uuidString == activeID)
                    if !profile.isPrimary {
                        Button("Remove profile", role: .destructive) { confirmDelete = true }
                    }
                }
            }
        }
        .navigationTitle(profile == nil ? "New profile" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let profile else { return }
            name = profile.name
            relationship = profile.relationship
            colorHex = profile.colorHex
            meals = profile.mealTimes
        }
        .confirmationDialog("Remove \(profile?.name ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove profile and their medicines", role: .destructive) {
                if let profile {
                    let ids = (profile.medications ?? []).map(\.id)
                    for id in ids { try? context.delete(model: DoseLog.self, where: #Predicate { $0.medicationID == id }) }
                    if activeID == profile.id.uuidString { activeID = "" }
                    context.delete(profile)
                    try? context.save()
                    NotificationService.shared.requestReschedule()
                }
                dismiss()
            }
        }
    }

    private var initials: String {
        let s = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    private func save() {
        let p = profile ?? Profile(name: name, relationship: relationship, isPrimary: false, colorHex: colorHex)
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.relationship = relationship
        p.colorHex = colorHex
        p.mealTimes = meals
        if profile == nil {
            context.insert(p)
            activeID = p.id.uuidString
        }
        try? context.save()
        NotificationService.shared.requestReschedule()
        dismiss()
    }
}

private struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Dosely is a reminder and record-keeping tool. It does not provide medical advice, diagnosis or treatment, does not recommend doses, and does not check for drug interactions.")
                Text("Prescription scanning can misread text, especially handwriting. Always compare what Dosely shows with your prescription and the medicine label, and follow the instructions from your doctor or pharmacist.")
                Text("If you miss a dose and aren't sure what to do, ask your pharmacist or doctor. In an emergency, call your local emergency number.")
            }
            .padding()
        }
        .navigationTitle("Medical disclaimer")
    }
}

private struct CreditsView: View {
    var body: some View {
        List {
            Section("RxNorm") {
                Text("This product uses publicly available data courtesy of the U.S. National Library of Medicine (NLM), National Institutes of Health, Department of Health and Human Services; NLM is not responsible for the product and does not endorse or recommend this or any other product.")
                    .font(.footnote)
            }
            Section("Indian brand names") {
                Text("Brand-to-generic matching uses a compact built-in list of common Indian brands, used only to recognise names on prescriptions.")
                    .font(.footnote)
            }
            Section("On-device processing") {
                Text("Text recognition uses Apple's Vision framework. When available, Apple Intelligence on-device models help structure prescriptions. Images never leave your iPhone.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Credits")
    }
}
