import Foundation

/// A person's meal times in minutes after midnight. Meal-relative doses resolve against these.
struct MealTimes: Codable, Hashable {
    var breakfast = 8 * 60
    var lunch = 13 * 60
    var dinner = 20 * 60
    var bedtime = 22 * 60

    func minutes(for anchor: MealAnchor) -> Int {
        switch anchor {
        case .breakfast: breakfast
        case .lunch: lunch
        case .dinner: dinner
        case .bedtime: bedtime
        }
    }
}

/// One intake within a day: either a fixed clock time or relative to a meal.
struct DoseTime: Codable, Hashable, Identifiable {
    var id = UUID()
    var minutes: Int = 8 * 60
    var amount: Double = 1
    var anchor: MealAnchor?
    var relation: MealRelation = .at

    func resolvedMinutes(_ meals: MealTimes) -> Int {
        guard let anchor else { return minutes }
        let base = meals.minutes(for: anchor)
        let offset = anchor == .bedtime ? 0 : relation.offset
        return min(max(base + offset, 0), 24 * 60 - 1)
    }

    func label(_ meals: MealTimes) -> String {
        guard let anchor else { return Fmt.time(minutes: minutes) }
        if anchor == .bedtime || relation == .at { return "\(anchor.label) time" }
        return "\(relation.label) \(anchor.rawValue)"
    }

    static func meal(_ anchor: MealAnchor, _ relation: MealRelation = .at, amount: Double = 1) -> DoseTime {
        DoseTime(amount: amount, anchor: anchor, relation: relation)
    }
}

struct Schedule: Codable, Hashable {
    var pattern: SchedulePattern = .daily
    /// Daily intakes. For `.everyXHours` the first entry is the first dose of the day and its amount.
    var times: [DoseTime] = [.meal(.breakfast)]
    var intervalHours: Int = 8
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    var weekdays: [Int] = [2]
    var dayInterval: Int = 2
    var startDate: Date = Calendar.current.startOfDay(for: .now)
    /// Last day of the course (inclusive). `nil` means ongoing.
    var endDate: Date?
    var foodTiming: FoodTiming = .any
    var maxDailyAsNeeded: Int?

    var isTimed: Bool { pattern != .asNeeded }

    /// Average amount taken per day, used for days-of-supply estimates.
    var averageDailyAmount: Double? {
        let perDay = times.reduce(0) { $0 + $1.amount }
        switch pattern {
        case .daily: return perDay
        case .weekdays: return perDay * Double(max(weekdays.count, 1)) / 7
        case .everyXDays: return perDay / Double(max(dayInterval, 1))
        case .everyXHours: return (times.first?.amount ?? 1) * 24 / Double(max(intervalHours, 1))
        case .asNeeded: return nil
        }
    }

    var durationDays: Int? {
        guard let endDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: endDate)).day ?? 0
        return days + 1
    }

    mutating func setDuration(days: Int?) {
        guard let days, days > 0 else { endDate = nil; return }
        endDate = Calendar.current.date(byAdding: .day, value: days - 1, to: Calendar.current.startOfDay(for: startDate))
    }

    func hasEnded(asOf date: Date = .now) -> Bool {
        guard let endDate else { return false }
        return Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: endDate)
    }

    func frequencyText(_ meals: MealTimes) -> String {
        switch pattern {
        case .daily:
            switch times.count {
            case 1: return "Once a day"
            case 2: return "Twice a day"
            case 3: return "3 times a day"
            default: return "\(times.count) times a day"
            }
        case .everyXHours:
            return "Every \(intervalHours) hours"
        case .weekdays:
            let symbols = Calendar.current.shortWeekdaySymbols
            let names = weekdays.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }
            return names.count == 7 ? "Every day" : names.joined(separator: ", ")
        case .everyXDays:
            return dayInterval == 2 ? "Every other day" : "Every \(dayInterval) days"
        case .asNeeded:
            return "As needed"
        }
    }

    func timesText(_ meals: MealTimes) -> String {
        switch pattern {
        case .asNeeded:
            return maxDailyAsNeeded.map { "Up to \($0) a day" } ?? "When required"
        case .everyXHours:
            return "From \(Fmt.time(minutes: times.first?.resolvedMinutes(meals) ?? 480))"
        default:
            return times.sorted { $0.resolvedMinutes(meals) < $1.resolvedMinutes(meals) }
                .map { Fmt.time(minutes: $0.resolvedMinutes(meals)) }
                .joined(separator: ", ")
        }
    }

    func durationText(asOf now: Date = .now) -> String? {
        guard let endDate else { return nil }
        let cal = Calendar.current
        if hasEnded(asOf: now) { return "Course finished" }
        let left = (cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: endDate)).day ?? 0) + 1
        if cal.startOfDay(for: startDate) > cal.startOfDay(for: now) {
            return "Starts \(startDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return left == 1 ? "Last day" : "\(left) days left"
    }
}
