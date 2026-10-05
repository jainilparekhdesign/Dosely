import Foundation
import Testing
@testable import Dosely

struct PrescriptionParserTests {
    @Test func indianPrescription() throws {
        let lines = [
            "Dr. Anil Sharma MBBS, MD",
            "City Clinic, Pune   Ph: 98200 12345",
            "Patient: R. Mehta   Age: 54",
            "Rx",
            "1. Tab Augmentin 625 mg  1-0-1  x 5 days  after food",
            "2. Tab Pan 40   1-0-0  before breakfast  x 5 days",
            "3. Tab Dolo 650  SOS",
            "4. Syp Ascoril  10 ml TDS x 5/7",
        ]
        let p = PrescriptionParser.parse(lines: lines)
        #expect(p.doctor == "Dr. Anil Sharma")
        #expect(p.medications.count == 4)

        let aug = p.medications[0]
        #expect(aug.name == "Augmentin")
        #expect(aug.genericName == "Amoxicillin + Clavulanate")
        #expect(aug.strength == "625 mg")
        #expect(aug.type == .tablet)
        #expect(aug.frequency?.slots.count == 2)
        #expect(aug.food == .after)
        #expect(aug.durationDays == 5)
        #expect(!aug.needsReview)

        let pan = p.medications[1]
        #expect(pan.name == "Pan")
        #expect(pan.genericName == "Pantoprazole")
        #expect(pan.strength == "40 mg")
        #expect(pan.strengthConfidence == .low)
        #expect(pan.food == .before)

        let dolo = p.medications[2]
        #expect(dolo.frequency?.pattern == .asNeeded)
        #expect(dolo.genericName == "Paracetamol")

        let syp = p.medications[3]
        #expect(syp.strength.isEmpty, "a dose in ml is not a strength")
        #expect(syp.type == .liquid)
        #expect(syp.doseAmount == 10)
        #expect(syp.doseUnit == "ml")
        #expect(syp.frequency?.slots.count == 3)
        #expect(syp.durationDays == 5)
    }

    @Test func usPrescription() throws {
        let lines = [
            "Jane Doe, MD — Family Medicine",
            "Date: 10/02/2026",
            "Amoxicillin 500mg PO TID x 10 days",
            "Metformin 500 mg BID with meals",
            "Ibuprofen 400 mg q6h PRN pain",
            "Lisinopril 10 mg QD",
        ]
        let p = PrescriptionParser.parse(lines: lines)
        #expect(p.medications.map(\.name) == ["Amoxicillin", "Metformin", "Ibuprofen", "Lisinopril"])
        #expect(p.medications[0].frequency?.slots.count == 3)
        #expect(p.medications[0].durationDays == 10)
        #expect(p.medications[1].food == .with)
        // q6h is matched before PRN: a fixed interval is the safer reading; the user confirms on review.
        #expect(p.medications[2].frequency?.pattern == .everyXHours)
        #expect(p.medications[3].frequency?.slots.count == 1)
        #expect(p.medications.allSatisfy { $0.nameConfidence == .high })
    }

    @Test func continuationLineMergesIntoPreviousMedicine() {
        let p = PrescriptionParser.parse(lines: ["Tab Telma 40 mg", "1-0-0 after breakfast — continue"])
        #expect(p.medications.count == 1)
        #expect(p.medications[0].frequency?.slots.map(\.anchor) == [.breakfast])
        #expect(p.medications[0].food == .after)
    }

    @Test func ocrTypoIsCorrectedButFlaggedMedium() throws {
        let p = PrescriptionParser.parse(lines: ["Amoxicilin 500 mg TDS"])
        let med = try #require(p.medications.first)
        #expect(med.name == "Amoxicillin")
        #expect(med.nameConfidence == .medium)
        #expect(med.notes.contains { $0.contains("corrected") })
    }

    @Test func unknownNameIsLowConfidence() throws {
        let p = PrescriptionParser.parse(lines: ["Tab Zyxofen 20 mg OD"])
        let med = try #require(p.medications.first)
        #expect(med.nameConfidence == .low)
        #expect(med.needsReview)
    }

    @Test func missingFrequencyIsFlagged() throws {
        let p = PrescriptionParser.parse(lines: ["Atorvastatin 20 mg"])
        let med = try #require(p.medications.first)
        #expect(med.frequency == nil)
        #expect(med.frequencyConfidence == .low)
    }

    @Test func ignoresHeaderLines() {
        let p = PrescriptionParser.parse(lines: ["Patient: John 45 yrs", "BP 130/80 mmHg", "Diagnosis: URTI", "Follow up after 5 days"])
        #expect(p.medications.isEmpty)
    }

    @Test func twoWordAndVitaminNames() {
        let p = PrescriptionParser.parse(lines: ["Cap Vitamin D3 60000 IU once a week x 8 weeks"])
        #expect(p.medications.first?.name == "Vitamin D3")
        #expect(p.medications.first?.durationDays == 56)
        #expect(p.medications.first?.type == .capsule)
    }

    @Test func draftScheduleFromParsedMedication() throws {
        let p = PrescriptionParser.parse(lines: ["Tab Augmentin 625 mg 1-0-1 x 5 days after food"])
        let med = try #require(p.medications.first)
        let today = Calendar.current.startOfDay(for: .now)
        let s = DraftMedication.schedule(from: med, today: today)
        #expect(s.pattern == .daily)
        #expect(s.times.map(\.anchor) == [.breakfast, .dinner])
        #expect(s.times.allSatisfy { $0.relation == .after })
        #expect(s.durationDays == 5)
        // After breakfast at 8:00 → 8:30
        #expect(s.times[0].resolvedMinutes(MealTimes()) == 8 * 60 + 30)
    }

    @Test func ambiguousNumericDateNeverInFuture() throws {
        let cal = Calendar.current
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        // Indian dd/mm: 03/10/2026 → 3 Oct (10 Mar would also be valid but is further back)
        let india = try #require(PrescriptionParser.firstDate(in: "Date: 03/10/2026", now: now))
        #expect(cal.dateComponents([.month, .day], from: india) == DateComponents(month: 10, day: 3))
        // US mm/dd: 10/02/2026 → 2 Oct (2 Oct is on/before today; 10 Feb is older)
        let us = try #require(PrescriptionParser.firstDate(in: "10/02/2026", now: now))
        #expect(cal.dateComponents([.month, .day], from: us) == DateComponents(month: 10, day: 2))
        // 25/09/2026 can only be dd/mm
        let unambiguous = try #require(PrescriptionParser.firstDate(in: "25/09/2026", now: now))
        #expect(cal.dateComponents([.month, .day], from: unambiguous) == DateComponents(month: 9, day: 25))
    }

    @Test func drugDatabaseHasNoDuplicateBrandKeysAndMatches() {
        #expect(DrugDatabase.match("CROCIN")?.generic == "Paracetamol")
        #expect(DrugDatabase.match("Metformin")?.exact == true)
        #expect(DrugDatabase.match("Atorvastatn")?.name == "Atorvastatin")
        #expect(DrugDatabase.match("xyz") == nil)
    }
}
