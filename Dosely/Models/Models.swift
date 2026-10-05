import Foundation
import SwiftData

@Model
final class Profile {
    var id: UUID = UUID()
    var name: String = ""
    /// e.g. "Me", "Mother", "Son". Used for caregiver sub-profiles.
    var relationship: String = ""
    var colorHex: String = "#008F8F"
    var isPrimary: Bool = false
    var breakfastMinutes: Int = 480
    var lunchMinutes: Int = 780
    var dinnerMinutes: Int = 1200
    var bedtimeMinutes: Int = 1320
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Medication.profile)
    var medications: [Medication]? = []

    @Relationship(deleteRule: .cascade, inverse: \Prescription.profile)
    var prescriptions: [Prescription]? = []

    init(name: String, relationship: String = "", isPrimary: Bool = false, colorHex: String = "#008F8F") {
        self.name = name
        self.relationship = relationship
        self.isPrimary = isPrimary
        self.colorHex = colorHex
    }

    var mealTimes: MealTimes {
        get { MealTimes(breakfast: breakfastMinutes, lunch: lunchMinutes, dinner: dinnerMinutes, bedtime: bedtimeMinutes) }
        set {
            breakfastMinutes = newValue.breakfast
            lunchMinutes = newValue.lunch
            dinnerMinutes = newValue.dinner
            bedtimeMinutes = newValue.bedtime
        }
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var genericName: String = ""
    var strength: String = ""
    var typeRaw: String = MedType.tablet.rawValue
    var unit: String = "tablet"
    var shapeRaw: String = PillShape.round.rawValue
    var colorHex: String = "#FFFFFF"
    var secondaryColorHex: String = "#3D7BF0"
    @Attribute(.externalStorage) var photoData: Data?
    var instructions: String = ""
    var doctor: String = ""
    var stockCount: Double?
    var refillThresholdDays: Int = 5
    var lastRefillAlert: Date?
    var isCritical: Bool = false
    var isPaused: Bool = false
    var scheduleData: Data = Data()
    var createdAt: Date = Date()

    var profile: Profile?
    var prescription: Prescription?

    init(name: String) {
        self.name = name
    }

    var type: MedType {
        get { MedType(rawValue: typeRaw) ?? .tablet }
        set { typeRaw = newValue.rawValue }
    }

    var shape: PillShape {
        get { PillShape(rawValue: shapeRaw) ?? .round }
        set { shapeRaw = newValue.rawValue }
    }

    var schedule: Schedule {
        get { (try? JSONDecoder().decode(Schedule.self, from: scheduleData)) ?? Schedule() }
        set { scheduleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var displayName: String {
        strength.isEmpty ? name : "\(name) \(strength)"
    }

    var mealTimes: MealTimes { profile?.mealTimes ?? MealTimes() }

    /// Active = not paused and the course hasn't finished.
    var isActive: Bool { !isPaused && !schedule.hasEnded() }

    var daysOfSupply: Double? {
        guard let stockCount, let daily = schedule.averageDailyAmount, daily > 0 else { return nil }
        return stockCount / daily
    }

    var needsRefill: Bool {
        guard isActive, let days = daysOfSupply else { return false }
        return days <= Double(refillThresholdDays)
    }
}

@Model
final class Prescription {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var doctor: String = ""
    var date: Date?
    /// "scan" or "manual"
    var source: String = "scan"
    var rawText: String = ""
    var createdAt: Date = Date()

    var profile: Profile?

    @Relationship(deleteRule: .nullify, inverse: \Medication.prescription)
    var medications: [Medication]? = []

    init(source: String = "scan") {
        self.source = source
    }
}

@Model
final class DoseLog {
    var id: UUID = UUID()
    var medicationID: UUID = UUID()
    /// For scheduled doses: the planned time (identity of the dose). For as-needed doses: the time taken.
    var scheduledAt: Date = Date()
    var statusRaw: String = DoseStatus.taken.rawValue
    var actualAt: Date?
    var amount: Double = 1
    var isAsNeeded: Bool = false
    var createdAt: Date = Date()

    init(medicationID: UUID, scheduledAt: Date, status: DoseStatus, actualAt: Date?, amount: Double, isAsNeeded: Bool = false) {
        self.medicationID = medicationID
        self.scheduledAt = scheduledAt
        self.statusRaw = status.rawValue
        self.actualAt = actualAt
        self.amount = amount
        self.isAsNeeded = isAsNeeded
    }

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }

    var key: String { DoseKey.make(medicationID, scheduledAt) }
}

enum DoseKey {
    static func make(_ medicationID: UUID, _ date: Date) -> String {
        "\(medicationID.uuidString)|\(Int(date.timeIntervalSince1970))"
    }
}
