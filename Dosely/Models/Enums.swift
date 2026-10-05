import Foundation

enum MedType: String, Codable, CaseIterable, Identifiable {
    case tablet, capsule, liquid, injection, drops, inhaler, cream, patch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tablet: "Tablet"
        case .capsule: "Capsule"
        case .liquid: "Syrup"
        case .injection: "Injection"
        case .drops: "Drops"
        case .inhaler: "Inhaler"
        case .cream: "Cream"
        case .patch: "Patch"
        }
    }

    /// Unit used for "dose per intake" and stock counting.
    var defaultUnit: String {
        switch self {
        case .tablet: "tablet"
        case .capsule: "capsule"
        case .liquid: "ml"
        case .injection: "injection"
        case .drops: "drop"
        case .inhaler: "puff"
        case .cream: "application"
        case .patch: "patch"
        }
    }

    var symbol: String {
        switch self {
        case .tablet: "pills.fill"
        case .capsule: "capsule.fill"
        case .liquid: "waterbottle.fill"
        case .injection: "syringe.fill"
        case .drops: "drop.fill"
        case .inhaler: "lungs.fill"
        case .cream: "hand.raised.fill"
        case .patch: "bandage.fill"
        }
    }

    /// Whether the stock count is a discrete count (pills) rather than a volume.
    var isCountable: Bool {
        switch self {
        case .tablet, .capsule, .injection, .patch: true
        default: false
        }
    }
}

enum PillShape: String, Codable, CaseIterable, Identifiable {
    case round, oval, oblong, diamond
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum DoseStatus: String, Codable {
    case taken, skipped
}

/// What the UI shows for a planned dose.
enum DisplayStatus: Equatable {
    case upcoming, due, taken, skipped, missed

    var label: String {
        switch self {
        case .upcoming: "Upcoming"
        case .due: "Due now"
        case .taken: "Taken"
        case .skipped: "Skipped"
        case .missed: "Missed"
        }
    }
}

enum FoodTiming: String, Codable, CaseIterable, Identifiable {
    case any, before, with, after, emptyStomach
    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: "No preference"
        case .before: "Before food"
        case .with: "With food"
        case .after: "After food"
        case .emptyStomach: "Empty stomach"
        }
    }
}

enum MealAnchor: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, bedtime
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum MealRelation: String, Codable, CaseIterable, Identifiable {
    case before, with, after, at
    var id: String { rawValue }

    /// Minutes relative to the meal time.
    var offset: Int {
        switch self {
        case .before: -30
        case .after: 30
        case .with, .at: 0
        }
    }

    var label: String {
        switch self {
        case .before: "Before"
        case .with: "With"
        case .after: "After"
        case .at: "At"
        }
    }
}

enum SchedulePattern: String, Codable, CaseIterable, Identifiable {
    case daily, everyXHours, weekdays, everyXDays, asNeeded
    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Every day"
        case .everyXHours: "Every few hours"
        case .weekdays: "Specific days"
        case .everyXDays: "Every few days"
        case .asNeeded: "As needed"
        }
    }
}
