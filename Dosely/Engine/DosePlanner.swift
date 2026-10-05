import Foundation

/// A scheduled intake of one medication at one time, joined with its log (if any).
struct PlannedDose: Identifiable {
    let medication: Medication
    let scheduledAt: Date
    let amount: Double
    let log: DoseLog?

    var id: String { DoseKey.make(medication.id, scheduledAt) }

    func status(now: Date = .now) -> DisplayStatus {
        DosePlanner.status(log: log, scheduledAt: scheduledAt, now: now)
    }
}

struct AdherenceStats: Equatable {
    var scheduled = 0
    var taken = 0
    var skipped = 0
    var missed = 0

    /// Taken ÷ scheduled (only counting doses that are already due).
    var rate: Double? { scheduled == 0 ? nil : Double(taken) / Double(scheduled) }

    static func + (l: AdherenceStats, r: AdherenceStats) -> AdherenceStats {
        AdherenceStats(scheduled: l.scheduled + r.scheduled, taken: l.taken + r.taken,
                       skipped: l.skipped + r.skipped, missed: l.missed + r.missed)
    }
}

enum DosePlanner {
    /// After this long without a log, a dose is considered missed.
    static let missedAfter: TimeInterval = 2 * 3600
    /// A dose becomes "due" this long before its time.
    static let dueWindow: TimeInterval = 15 * 60

    static func status(log: DoseLog?, scheduledAt: Date, now: Date) -> DisplayStatus {
        if let log {
            return log.status == .taken ? .taken : .skipped
        }
        if now > scheduledAt.addingTimeInterval(missedAfter) { return .missed }
        if now >= scheduledAt.addingTimeInterval(-dueWindow) { return .due }
        return .upcoming
    }

    static func logIndex(_ logs: [DoseLog]) -> [String: DoseLog] {
        var index: [String: DoseLog] = [:]
        for log in logs where !log.isAsNeeded { index[log.key] = log }
        return index
    }

    /// Doses for `meds` on `day`. Doses planned before a medication was added are hidden unless logged,
    /// so adding a medicine at 3 PM doesn't show this morning's dose as missed.
    static func doses(for meds: [Medication], on day: Date, logs: [String: DoseLog], calendar: Calendar = .current) -> [PlannedDose] {
        meds.filter { !$0.isPaused }.flatMap { med in
            ScheduleEngine.occurrences(of: med.schedule, on: day, meals: med.mealTimes, calendar: calendar).compactMap { occ in
                let log = logs[DoseKey.make(med.id, occ.date)]
                if log == nil && occ.date < med.createdAt.addingTimeInterval(-60) { return nil }
                return PlannedDose(medication: med, scheduledAt: occ.date, amount: occ.amount, log: log)
            }
        }
        .sorted { ($0.scheduledAt, $0.medication.name) < ($1.scheduledAt, $1.medication.name) }
    }

    static func stats(for doses: [PlannedDose], now: Date = .now) -> AdherenceStats {
        var s = AdherenceStats()
        for dose in doses {
            switch dose.status(now: now) {
            case .taken: s.scheduled += 1; s.taken += 1
            case .skipped: s.scheduled += 1; s.skipped += 1
            case .missed: s.scheduled += 1; s.missed += 1
            case .upcoming, .due: break
            }
        }
        return s
    }

    static func stats(for meds: [Medication], from: Date, to: Date, logs: [String: DoseLog], now: Date = .now, calendar: Calendar = .current) -> AdherenceStats {
        var total = AdherenceStats()
        var day = calendar.startOfDay(for: from)
        while day < to && day <= now {
            total = total + stats(for: doses(for: meds, on: day, logs: logs, calendar: calendar), now: now)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// Consecutive fully-adherent days ending yesterday (or today if today is already complete).
    static func streak(for meds: [Medication], logs: [String: DoseLog], now: Date = .now, calendar: Calendar = .current) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: now)
        let today = doses(for: meds, on: day, logs: logs, calendar: calendar)
        let todayDone = !today.isEmpty && today.allSatisfy { $0.status(now: now) == .taken }
        if todayDone { count += 1 }
        for _ in 0..<365 {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
            let ds = doses(for: meds, on: day, logs: logs, calendar: calendar)
            if ds.isEmpty { continue }
            if ds.allSatisfy({ $0.status(now: now) == .taken }) { count += 1 } else { break }
            if day < (meds.map(\.createdAt).min() ?? day) { break }
        }
        return count
    }

    /// Part of the day a dose falls in, for grouping on the Today screen.
    static func period(for date: Date, calendar: Calendar = .current) -> DayPeriod {
        switch calendar.component(.hour, from: date) {
        case 0..<12: .morning
        case 12..<17: .afternoon
        case 17..<21: .evening
        default: .night
        }
    }
}

enum DayPeriod: Int, CaseIterable, Identifiable {
    case morning, afternoon, evening, night
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }
}
