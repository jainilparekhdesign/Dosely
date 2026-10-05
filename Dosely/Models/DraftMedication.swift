import Foundation
import Observation

/// Editable copy of a medication. Used by the editor and the scan review screen;
/// nothing touches the database until `apply(to:)` is called on save.
@Observable
final class DraftMedication: Identifiable {
    let id = UUID()
    var name = ""
    var genericName = ""
    var strength = ""
    var type: MedType = .tablet
    var unit = MedType.tablet.defaultUnit
    var shape: PillShape = .round
    var colorHex = "#FFFFFF"
    var secondaryColorHex = "#3D7BF0"
    var photoData: Data?
    var instructions = ""
    var doctor = ""
    var tracksStock = false
    var stockCount: Double = 30
    var refillThresholdDays = 5
    var isCritical = false
    var schedule = Schedule()

    // Scan review state
    var include = true
    var confirmed = true
    var nameConfidence: Confidence = .high
    var strengthConfidence: Confidence = .high
    var frequencyConfidence: Confidence = .high
    var notes: [String] = []
    var sourceLine = ""

    init() {}

    init(from med: Medication) {
        name = med.name
        genericName = med.genericName
        strength = med.strength
        type = med.type
        unit = med.unit
        shape = med.shape
        colorHex = med.colorHex
        secondaryColorHex = med.secondaryColorHex
        photoData = med.photoData
        instructions = med.instructions
        doctor = med.doctor
        tracksStock = med.stockCount != nil
        stockCount = med.stockCount ?? 30
        refillThresholdDays = med.refillThresholdDays
        isCritical = med.isCritical
        schedule = med.schedule
    }

    static let palette: [String] = ["#FFFFFF", "#F5D76E", "#F29B38", "#E5534B", "#F28BB5", "#9B6BDF",
                                    "#3D7BF0", "#2FB5C9", "#3DBE7A", "#8D6E63", "#9E9E9E", "#2B2B2B"]

    /// Build a draft from scanned text, assigning distinct default colours so medicines look different.
    init(parsed: ParsedMedication, doctor: String, index: Int) {
        name = parsed.name
        genericName = parsed.genericName
        strength = parsed.strength
        type = parsed.type ?? .tablet
        unit = parsed.doseUnit.flatMap { ShorthandDecoder.type(forDoseUnit: $0) == type ? $0 : nil } ?? type.defaultUnit
        self.doctor = doctor
        let colors = Self.palette
        colorHex = type == .capsule ? colors[(index * 5 + 1) % colors.count] : (index == 0 ? "#FFFFFF" : colors[(index * 5) % colors.count])
        secondaryColorHex = colors[(index * 7 + 6) % colors.count]
        shape = index % 3 == 1 ? .oval : (index % 3 == 2 ? .oblong : .round)
        nameConfidence = parsed.nameConfidence
        strengthConfidence = parsed.strengthConfidence
        frequencyConfidence = parsed.frequencyConfidence
        notes = parsed.notes
        sourceLine = parsed.sourceLine
        confirmed = !parsed.needsReview
        schedule = Self.schedule(from: parsed)
        if let food = parsed.food, food != .any { instructions = food.label }
    }

    static func schedule(from parsed: ParsedMedication, today: Date = .now) -> Schedule {
        var s = Schedule()
        s.startDate = Calendar.current.startOfDay(for: today)
        s.foodTiming = parsed.food ?? .any
        let relation: MealRelation = switch parsed.food {
        case .before, .emptyStomach: .before
        case .after: .after
        case .with: .with
        default: .at
        }
        let amount = parsed.doseAmount ?? 1
        let freq = parsed.frequency ?? DecodedFrequency(pattern: .daily, slots: [.init(anchor: .breakfast)], matched: "")
        s.pattern = freq.pattern
        switch freq.pattern {
        case .everyXHours:
            s.intervalHours = freq.intervalHours ?? 8
            s.times = [DoseTime(minutes: 8 * 60, amount: amount)]
        case .asNeeded:
            s.times = [DoseTime(minutes: 8 * 60, amount: amount)]
        case .weekdays:
            s.weekdays = [Calendar.current.component(.weekday, from: today)]
            s.times = [.meal(.breakfast, relation, amount: amount)]
        case .everyXDays:
            s.dayInterval = freq.dayInterval ?? 2
            s.times = [.meal(.breakfast, relation, amount: amount)]
        case .daily:
            let slots = freq.slots.isEmpty ? [DecodedFrequency.Slot(anchor: .breakfast)] : freq.slots
            s.times = slots.map { .meal($0.anchor, relation, amount: $0.amount ?? amount) }
        }
        s.setDuration(days: parsed.durationDays)
        return s
    }

    var needsAttention: Bool { nameConfidence == .low || strengthConfidence == .low || frequencyConfidence == .low }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (schedule.pattern == .asNeeded || !schedule.times.isEmpty)
    }

    func apply(to med: Medication) {
        med.name = name.trimmingCharacters(in: .whitespaces)
        med.genericName = genericName
        med.strength = strength.trimmingCharacters(in: .whitespaces)
        med.type = type
        med.unit = unit.isEmpty ? type.defaultUnit : unit
        med.shape = shape
        med.colorHex = colorHex
        med.secondaryColorHex = secondaryColorHex
        med.photoData = photoData
        med.instructions = instructions
        med.doctor = doctor
        med.stockCount = tracksStock ? stockCount : nil
        med.refillThresholdDays = refillThresholdDays
        med.isCritical = isCritical
        med.schedule = schedule
    }
}
