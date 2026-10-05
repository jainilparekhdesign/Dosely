import Foundation
import Testing
@testable import Dosely

struct ScheduleEngineTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func hm(_ date: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    @Test func dailyMealRelativeTimes() {
        var s = Schedule()
        s.startDate = day(2026, 10, 1)
        s.times = [.meal(.breakfast, .after), .meal(.dinner, .before, amount: 2)]
        let occ = ScheduleEngine.occurrences(of: s, on: day(2026, 10, 3), meals: MealTimes(), calendar: cal)
        #expect(occ.map { hm($0.date) } == ["08:30", "19:30"])
        #expect(occ.map(\.amount) == [1, 2])
    }

    @Test func respectsStartAndEnd() {
        var s = Schedule()
        s.startDate = day(2026, 10, 5)
        s.endDate = day(2026, 10, 9)
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 4), meals: MealTimes(), calendar: cal).isEmpty)
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 9), meals: MealTimes(), calendar: cal).count == 1)
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 10), meals: MealTimes(), calendar: cal).isEmpty)
    }

    @Test func weekdays() {
        var s = Schedule()
        s.pattern = .weekdays
        s.weekdays = [2, 4] // Mon, Wed
        s.startDate = day(2026, 10, 1)
        // Oct 5 2026 is a Monday
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 5), meals: MealTimes(), calendar: cal).count == 1)
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 6), meals: MealTimes(), calendar: cal).isEmpty)
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 7), meals: MealTimes(), calendar: cal).count == 1)
    }

    @Test func everyOtherDay() {
        var s = Schedule()
        s.pattern = .everyXDays
        s.dayInterval = 2
        s.startDate = day(2026, 10, 1)
        let counts = (1...6).map { ScheduleEngine.occurrences(of: s, on: day(2026, 10, $0), meals: MealTimes(), calendar: cal).count }
        #expect(counts == [1, 0, 1, 0, 1, 0])
    }

    @Test func everyEightHoursCarriesAcrossDays() {
        var s = Schedule()
        s.pattern = .everyXHours
        s.intervalHours = 8
        s.times = [DoseTime(minutes: 10 * 60)]
        s.startDate = day(2026, 10, 1)
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 1), meals: MealTimes(), calendar: cal).map { hm($0.date) } == ["10:00", "18:00"])
        #expect(ScheduleEngine.occurrences(of: s, on: day(2026, 10, 2), meals: MealTimes(), calendar: cal).map { hm($0.date) } == ["02:00", "10:00", "18:00"])
    }

    @Test func dstFallBackDoesNotDuplicateOrShiftDailyDoses() {
        // US DST ends Nov 1 2026: wall-clock times stay put and nothing is duplicated.
        var s = Schedule()
        s.startDate = day(2026, 10, 25)
        s.times = [.meal(.breakfast), .meal(.bedtime)]
        let occ = ScheduleEngine.occurrences(of: s, on: day(2026, 11, 1), meals: MealTimes(), calendar: cal)
        #expect(occ.map { hm($0.date) } == ["08:00", "22:00"])
    }

    @Test func dstSpringForwardKeepsDoseInMissingHour() {
        var s = Schedule()
        s.startDate = day(2026, 3, 1)
        s.times = [DoseTime(minutes: 2 * 60 + 30)] // 2:30 AM doesn't exist on Mar 8 2026
        let occ = ScheduleEngine.occurrences(of: s, on: day(2026, 3, 8), meals: MealTimes(), calendar: cal)
        #expect(occ.count == 1)
    }

    @Test func asNeededHasNoOccurrences() {
        var s = Schedule()
        s.pattern = .asNeeded
        #expect(ScheduleEngine.occurrences(of: s, on: .now, meals: MealTimes(), calendar: cal).isEmpty)
    }

    @Test func averageDailyAmount() {
        var s = Schedule()
        s.times = [.meal(.breakfast, amount: 1), .meal(.dinner, amount: 2)]
        #expect(s.averageDailyAmount == 3)
        s.pattern = .everyXHours
        s.intervalHours = 8
        #expect(s.averageDailyAmount == 3)
        s.pattern = .everyXDays
        s.dayInterval = 2
        #expect(s.averageDailyAmount == 1.5)
    }

    @Test func durationHelpers() {
        var s = Schedule()
        s.startDate = day(2026, 10, 1)
        s.setDuration(days: 5)
        #expect(s.durationDays == 5)
        #expect(s.hasEnded(asOf: day(2026, 10, 5).addingTimeInterval(3600)) == false)
    }

    @Test func statusResolution() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        #expect(DosePlanner.status(log: nil, scheduledAt: t, now: t.addingTimeInterval(-3600)) == .upcoming)
        #expect(DosePlanner.status(log: nil, scheduledAt: t, now: t.addingTimeInterval(-60)) == .due)
        #expect(DosePlanner.status(log: nil, scheduledAt: t, now: t.addingTimeInterval(3600)) == .due)
        #expect(DosePlanner.status(log: nil, scheduledAt: t, now: t.addingTimeInterval(3 * 3600)) == .missed)
    }

    @Test func formatting() {
        #expect(Fmt.amount(0.5) == "½")
        #expect(Fmt.amount(1.5) == "1½")
        #expect(Fmt.dose(2, unit: "tablet") == "2 tablets")
        #expect(Fmt.dose(1, unit: "tablet") == "1 tablet")
        #expect(Fmt.dose(10, unit: "ml") == "10 ml")
    }
}
