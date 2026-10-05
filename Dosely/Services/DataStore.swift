import Foundation
import SwiftData

@MainActor
enum DataStore {
    static let schema = Schema([Profile.self, Medication.self, Prescription.self, DoseLog.self])

    /// One container shared by the UI and notification-action handlers.
    static let container: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            protectStoreDirectory(config.url.deletingLastPathComponent())
            return container
        } catch {
            fatalError("Could not open the Dosely database: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }

    /// Health data: keep the store encrypted at rest whenever the device is locked after first unlock
    /// (notification actions must still be able to write while the phone is locked).
    private static func protectStoreDirectory(_ url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }

    static func profiles() -> [Profile] {
        (try? context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    static func medication(id: UUID) -> Medication? {
        var d = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    static func logs(from: Date, to: Date) -> [DoseLog] {
        let d = FetchDescriptor<DoseLog>(predicate: #Predicate { $0.scheduledAt >= from && $0.scheduledAt < to })
        return (try? context.fetch(d)) ?? []
    }

    static func log(medicationID: UUID, scheduledAt: Date) -> DoseLog? {
        var d = FetchDescriptor<DoseLog>(predicate: #Predicate { $0.medicationID == medicationID && $0.scheduledAt == scheduledAt && !$0.isAsNeeded })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    static func save() {
        try? context.save()
    }
}

/// User preferences (UserDefaults keys used with @AppStorage).
enum Prefs {
    static let onboarded = "onboarded"
    static let activeProfileID = "activeProfileID"
    static let followUpEnabled = "followUpEnabled"
    static let followUpMinutes = "followUpMinutes"
    static let quietHoursEnabled = "quietHoursEnabled"
    static let quietStart = "quietStart"
    static let quietEnd = "quietEnd"
    static let useOnDeviceAI = "useOnDeviceAI"
    static let verifyWithRxNorm = "verifyWithRxNorm"
    static let appLock = "appLock"

    static func register() {
        UserDefaults.standard.register(defaults: [
            followUpEnabled: true,
            followUpMinutes: 30,
            quietHoursEnabled: false,
            quietStart: 23 * 60,
            quietEnd: 7 * 60,
            useOnDeviceAI: true,
            verifyWithRxNorm: false,
            appLock: false,
        ])
    }

    static var followUp: Int? {
        let d = UserDefaults.standard
        return d.bool(forKey: followUpEnabled) ? max(d.integer(forKey: followUpMinutes), 5) : nil
    }

    /// Follow-up nudges are suppressed in quiet hours (the dose reminder itself always fires).
    static func isQuiet(_ date: Date) -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: quietHoursEnabled) else { return false }
        let m = Fmt.minutes(from: date)
        let s = d.integer(forKey: quietStart), e = d.integer(forKey: quietEnd)
        return s <= e ? (m >= s && m < e) : (m >= s || m < e)
    }
}
