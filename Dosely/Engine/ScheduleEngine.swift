import Foundation

struct Occurrence: Hashable {
    let date: Date
    let amount: Double
}

/// Pure schedule maths. Times are wall-clock (8:00 stays 8:00 after a timezone or DST change);
/// interval schedules ("every 8 hours") use true elapsed hours from the course start.
enum ScheduleEngine {
    static func occurrences(of schedule: Schedule, on day: Date, meals: MealTimes, calendar: Calendar = .current) -> [Occurrence] {
        let dayStart = calendar.startOfDay(for: day)
        let startDay = calendar.startOfDay(for: schedule.startDate)
        if dayStart < startDay { return [] }
        if let end = schedule.endDate, dayStart > calendar.startOfDay(for: end) { return [] }

        switch schedule.pattern {
        case .asNeeded:
            return []
        case .daily:
            return clockTimes(schedule, dayStart, meals, calendar)
        case .weekdays:
            let weekday = calendar.component(.weekday, from: dayStart)
            return schedule.weekdays.contains(weekday) ? clockTimes(schedule, dayStart, meals, calendar) : []
        case .everyXDays:
            let days = calendar.dateComponents([.day], from: startDay, to: dayStart).day ?? 0
            return days % max(schedule.dayInterval, 1) == 0 ? clockTimes(schedule, dayStart, meals, calendar) : []
        case .everyXHours:
            return intervalTimes(schedule, dayStart, startDay, meals, calendar)
        }
    }

    /// All occurrences in [from, to), across days.
    static func occurrences(of schedule: Schedule, from: Date, to: Date, meals: MealTimes, calendar: Calendar = .current) -> [Occurrence] {
        var result: [Occurrence] = []
        var day = calendar.startOfDay(for: from)
        while day < to {
            result += occurrences(of: schedule, on: day, meals: meals, calendar: calendar).filter { $0.date >= from && $0.date < to }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private static func clockTimes(_ s: Schedule, _ dayStart: Date, _ meals: MealTimes, _ cal: Calendar) -> [Occurrence] {
        var seen = Set<Date>()
        return s.times
            .map { ($0.resolvedMinutes(meals), $0.amount) }
            .sorted { $0.0 < $1.0 }
            .compactMap { minutes, amount in
                let date = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart)
                    ?? dayStart.addingTimeInterval(TimeInterval(minutes * 60))
                guard seen.insert(date).inserted else { return nil }
                return Occurrence(date: date, amount: amount)
            }
    }

    private static func intervalTimes(_ s: Schedule, _ dayStart: Date, _ startDay: Date, _ meals: MealTimes, _ cal: Calendar) -> [Occurrence] {
        let first = s.times.first ?? DoseTime()
        let firstMinutes = first.resolvedMinutes(meals)
        guard let anchor = cal.date(bySettingHour: firstMinutes / 60, minute: firstMinutes % 60, second: 0, of: startDay),
              let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let step = TimeInterval(max(s.intervalHours, 1) * 3600)
        var k = max(0, floor(dayStart.timeIntervalSince(anchor) / step))
        var result: [Occurrence] = []
        var t = anchor.addingTimeInterval(k * step)
        while t < dayEnd {
            if t >= dayStart { result.append(Occurrence(date: t, amount: first.amount)) }
            k += 1
            t = anchor.addingTimeInterval(k * step)
        }
        return result
    }
}
