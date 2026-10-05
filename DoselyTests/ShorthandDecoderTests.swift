import Foundation
import Testing
@testable import Dosely

struct ShorthandDecoderTests {
    @Test("US and Indian frequency shorthand", arguments: [
        ("OD", 1), ("QD", 1), ("once daily", 1),
        ("BD", 2), ("b.d.", 2), ("BID", 2), ("twice a day", 2),
        ("TDS", 3), ("TID", 3), ("t.d.s", 3), ("thrice daily", 3),
        ("QID", 4), ("four times a day", 4),
        ("HS", 1),
    ])
    func dailyCounts(text: String, expected: Int) throws {
        let f = try #require(ShorthandDecoder.frequency(in: "Tab X 500 mg \(text)"))
        #expect(f.pattern == .daily)
        #expect(f.slots.count == expected)
    }

    @Test func bedtime() throws {
        let f = try #require(ShorthandDecoder.frequency(in: "1 tab HS"))
        #expect(f.slots.map(\.anchor) == [.bedtime])
    }

    @Test func dosingPatternThreePart() throws {
        let f = try #require(ShorthandDecoder.frequency(in: "Augmentin 625 1-0-1 x 5 days"))
        #expect(f.pattern == .daily)
        #expect(f.slots.map(\.anchor) == [.breakfast, .dinner])
        #expect(f.slots.map(\.amount) == [1, 1])
    }

    @Test func dosingPatternDifferentAmounts() throws {
        let f = try #require(ShorthandDecoder.frequency(in: "1-0-2"))
        #expect(f.slots.map(\.amount) == [1, 2])
    }

    @Test func dosingPatternHalfAndFourPart() throws {
        let half = try #require(ShorthandDecoder.frequency(in: "½-0-½"))
        #expect(half.slots.map(\.amount) == [0.5, 0.5])
        let four = try #require(ShorthandDecoder.frequency(in: "1-1-1-1"))
        #expect(four.slots.map(\.anchor) == [.breakfast, .lunch, .dinner, .bedtime])
    }

    @Test func datesAreNotDosingPatterns() {
        #expect(ShorthandDecoder.dosingPattern(in: "date: 12-10-2026") == nil)
    }

    @Test("Every X hours", arguments: [("q8h", 8), ("Q6H", 6), ("every 12 hours", 12), ("q.8.h", 8)])
    func interval(text: String, hours: Int) throws {
        let f = try #require(ShorthandDecoder.frequency(in: text))
        #expect(f.pattern == .everyXHours)
        #expect(f.intervalHours == hours)
    }

    @Test("As needed", arguments: ["SOS", "PRN", "as needed", "when required"])
    func asNeeded(text: String) throws {
        #expect(try #require(ShorthandDecoder.frequency(in: "Paracetamol 650 mg \(text)")).pattern == .asNeeded)
    }

    @Test func alternateDays() throws {
        let f = try #require(ShorthandDecoder.frequency(in: "1 tab on alternate days"))
        #expect(f.pattern == .everyXDays)
        #expect(f.dayInterval == 2)
    }

    @Test func weekly() throws {
        #expect(try #require(ShorthandDecoder.frequency(in: "Vitamin D3 60000 IU once a week")).pattern == .weekdays)
    }

    @Test func noFrequency() {
        #expect(ShorthandDecoder.frequency(in: "Amoxicillin 500 mg") == nil)
    }

    @Test("Durations", arguments: [
        ("x 5 days", 5), ("for 7 days", 7), ("5/7", 5), ("2/52", 14), ("1/12", 30),
        ("x 2 weeks", 14), ("for 1 month", 30), ("10 d", 10),
    ])
    func durations(text: String, days: Int) {
        #expect(ShorthandDecoder.durationDays(in: "1-0-1 \(text)") == days)
    }

    @Test func ongoingHasNoDuration() {
        #expect(ShorthandDecoder.durationDays(in: "Metformin 500 mg BD continue") == nil)
        #expect(ShorthandDecoder.durationDays(in: "Metformin 500 mg BD") == nil)
    }

    @Test("Food timing", arguments: [
        ("after food", FoodTiming.after), ("PC", .after), ("before meals", .before), ("a.c.", .before),
        ("empty stomach", .emptyStomach), ("with food", .with),
    ])
    func food(text: String, expected: FoodTiming) {
        #expect(ShorthandDecoder.foodTiming(in: "1 tab BD \(text)") == expected)
    }

    @Test func strength() {
        #expect(ShorthandDecoder.strength(in: "Amoxicillin 500mg TID")?.text == "500 mg")
        #expect(ShorthandDecoder.strength(in: "Augmentin 500/125 mg")?.text == "500/125 mg")
        #expect(ShorthandDecoder.strength(in: "Syp Calpol 250 mg/5 ml")?.text == "250 mg/5 ml")
        #expect(ShorthandDecoder.strength(in: "Levothyroxine 50 mcg")?.text == "50 mcg")
        #expect(ShorthandDecoder.strength(in: "Vitamin D3 60000 IU")?.text == "60000 IU")
    }

    @Test func dose() {
        #expect(ShorthandDecoder.dose(in: "take 2 tabs BD") == .init(amount: 2, unit: "tablet"))
        #expect(ShorthandDecoder.dose(in: "10 ml TDS") == .init(amount: 10, unit: "ml"))
        #expect(ShorthandDecoder.dose(in: "2 puffs BD") == .init(amount: 2, unit: "puff"))
        #expect(ShorthandDecoder.dose(in: "½ tab HS") == .init(amount: 0.5, unit: "tablet"))
    }

    @Test func formPrefix() {
        #expect(ShorthandDecoder.formPrefix(in: "Tab. Dolo 650")?.type == .tablet)
        #expect(ShorthandDecoder.formPrefix(in: "Cap Pan-D")?.type == .capsule)
        #expect(ShorthandDecoder.formPrefix(in: "Syp. Ascoril")?.type == .liquid)
        #expect(ShorthandDecoder.formPrefix(in: "Inj Insulin")?.type == .injection)
        #expect(ShorthandDecoder.formPrefix(in: "Cream Candid")?.type == .cream)
        #expect(ShorthandDecoder.formPrefix(in: "Tablet Augmentin")?.type == .tablet)
        #expect(ShorthandDecoder.formPrefix(in: "Dolo 650") == nil)
    }
}
