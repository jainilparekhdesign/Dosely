#if DEBUG
import SwiftData
import SwiftUI
import UserNotifications

/// Debug-only launch arguments for demos and screenshots:
///   -seedDemo           fill the app with sample profiles, medicines and 3 weeks of history
///   -startTab <name>    today | medications | history | settings
///   -scanSample <path>  open the scan flow on an image file
enum DebugSupport {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    @MainActor
    static func apply(router: Router) {
        if arguments.contains("-seedDemo") { seedDemo() }
        if arguments.contains("-provisionalNotifications") {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional])
                await NotificationService.shared.rescheduleAll()
            }
        }
        switch value(after: "-startTab") {
        case "medications": router.tab = .medications
        case "history": router.tab = .history
        case "settings": router.tab = .settings
        default: break
        }
        if value(after: "-scanSample") != nil { router.showScan = true }
    }

    static var sampleScanImage: UIImage? {
        value(after: "-scanSample").flatMap { UIImage(contentsOfFile: $0) }
    }

    @MainActor
    static func seedDemo() {
        let context = DataStore.context
        guard DataStore.profiles().isEmpty else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let created = cal.date(byAdding: .day, value: -21, to: today)!

        let me = Profile(name: "Jainil", relationship: "Me", isPrimary: true)
        let mom = Profile(name: "Mom", relationship: "Mother", isPrimary: false, colorHex: "#9B6BDF")
        context.insert(me)
        context.insert(mom)

        func med(_ name: String, _ strength: String, _ type: MedType, _ color: String, _ second: String = "#3D7BF0",
                 shape: PillShape = .round, profile: Profile, schedule: Schedule, stock: Double? = nil,
                 generic: String = "", critical: Bool = false, created: Date) -> Medication {
            let m = Medication(name: name)
            m.strength = strength
            m.type = type
            m.unit = type.defaultUnit
            m.colorHex = color
            m.secondaryColorHex = second
            m.shape = shape
            m.genericName = generic
            m.stockCount = stock
            m.isCritical = critical
            m.schedule = schedule
            m.profile = profile
            m.createdAt = created
            context.insert(m)
            return m
        }

        var bd = Schedule(); bd.startDate = created
        bd.times = [.meal(.breakfast, .after), .meal(.dinner, .after)]; bd.foodTiming = .after
        let metformin = med("Metformin", "500 mg", .tablet, "#FFFFFF", shape: .oblong, profile: me, schedule: bd, stock: 7, created: created)

        var hs = Schedule(); hs.startDate = created; hs.times = [.meal(.bedtime)]
        let atorva = med("Atorvastatin", "20 mg", .tablet, "#F5D76E", shape: .oval, profile: me, schedule: hs, stock: 40, created: created)

        var course = Schedule(); course.startDate = cal.date(byAdding: .day, value: -2, to: today)!
        course.times = [.meal(.breakfast, .after), .meal(.dinner, .after)]; course.foodTiming = .after; course.setDuration(days: 5)
        let augmentin = med("Augmentin", "625 mg", .tablet, "#F29B38", shape: .oblong, profile: me, schedule: course,
                            generic: "Amoxicillin + Clavulanate", created: course.startDate)

        var od = Schedule(); od.startDate = created; od.times = [.meal(.breakfast, .before)]; od.foodTiming = .before
        let pan = med("Pan", "40 mg", .capsule, "#E5534B", "#F5D76E", profile: me, schedule: od, stock: 25,
                      generic: "Pantoprazole", created: created)

        var weekly = Schedule(); weekly.pattern = .weekdays; weekly.startDate = created
        weekly.weekdays = [1]; weekly.times = [.meal(.breakfast)]
        let vitD = med("Vitamin D3", "60000 IU", .capsule, "#3DBE7A", "#F5D76E", profile: me, schedule: weekly, created: created)

        var prn = Schedule(); prn.pattern = .asNeeded; prn.times = [DoseTime(amount: 1)]; prn.maxDailyAsNeeded = 4; prn.startDate = created
        _ = med("Dolo", "650 mg", .tablet, "#FFFFFF", profile: me, schedule: prn, generic: "Paracetamol", created: created)

        var momBP = Schedule(); momBP.startDate = created; momBP.times = [.meal(.breakfast, .after)]
        let telma = med("Telma", "40 mg", .tablet, "#3D7BF0", profile: mom, schedule: momBP, stock: 20,
                        generic: "Telmisartan", critical: true, created: created)
        var momThyroid = Schedule(); momThyroid.startDate = created; momThyroid.times = [DoseTime(minutes: 6 * 60 + 30)]
        momThyroid.foodTiming = .emptyStomach
        let thyro = med("Thyronorm", "50 mcg", .tablet, "#F28BB5", profile: mom, schedule: momThyroid, generic: "Levothyroxine", created: created)

        // Deterministic history: mostly taken, a few missed/skipped.
        var seed: UInt64 = 42
        func rand() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        let now = Date.now
        for m in [metformin, atorva, augmentin, pan, vitD, telma, thyro] {
            for occ in ScheduleEngine.occurrences(of: m.schedule, from: m.createdAt, to: now, meals: m.mealTimes) {
                if now.timeIntervalSince(occ.date) < 3600 { continue }
                let r = rand()
                if r < 0.86 {
                    context.insert(DoseLog(medicationID: m.id, scheduledAt: occ.date, status: .taken,
                                           actualAt: occ.date.addingTimeInterval(rand() * 1800), amount: occ.amount))
                } else if r < 0.92 {
                    context.insert(DoseLog(medicationID: m.id, scheduledAt: occ.date, status: .skipped, actualAt: occ.date, amount: occ.amount))
                }
            }
        }
        try? context.save()
        UserDefaults.standard.set(me.id.uuidString, forKey: Prefs.activeProfileID)
        UserDefaults.standard.set(true, forKey: Prefs.onboarded)
    }
}
struct DebugScreen: Identifiable {
    let name: String
    var id: String { name }
}

/// -debugScreen detail:<Name> | editor:<Name> | new | report
struct DebugScreenView: View {
    let screen: String
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    var body: some View {
        let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
        let med = parts.count > 1 ? meds.first { $0.name == parts[1] } : nil
        switch parts[0] {
        case "detail":
            if let med { NavigationStack { MedicationDetailView(medication: med) } }
        case "editor":
            NavigationStack { MedicationEditorView(medication: med) }
        case "report":
            ReportView(profile: profiles.first(where: \.isPrimary), meds: meds.filter { $0.profile?.isPrimary == true })
        default:
            Text("Unknown debug screen")
        }
    }
}
#endif
