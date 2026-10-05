import Foundation
import SwiftData
import Testing
@testable import Dosely

@MainActor
@Suite(.serialized)
struct DoseActionsTests {
    private func makeMed(stock: Double?) -> Medication {
        let med = Medication(name: "Test-\(UUID().uuidString.prefix(6))")
        med.stockCount = stock
        var s = Schedule()
        s.startDate = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        s.times = [.meal(.breakfast), .meal(.dinner)]
        med.schedule = s
        med.createdAt = s.startDate
        DataStore.context.insert(med)
        DataStore.save()
        return med
    }

    @Test func takenDecrementsStockAndUndoRestores() throws {
        let med = makeMed(stock: 10)
        let at = Calendar.current.date(byAdding: .hour, value: -30, to: .now)!
        DoseActions.mark(.taken, medicationID: med.id, scheduledAt: at, amount: 2)
        #expect(med.stockCount == 8)
        #expect(DataStore.log(medicationID: med.id, scheduledAt: at)?.status == .taken)

        // Marking taken twice must not double-count.
        DoseActions.mark(.taken, medicationID: med.id, scheduledAt: at, amount: 2)
        #expect(med.stockCount == 8)

        // Changing to skipped gives the pills back.
        DoseActions.mark(.skipped, medicationID: med.id, scheduledAt: at, amount: 2)
        #expect(med.stockCount == 10)
        #expect(DataStore.log(medicationID: med.id, scheduledAt: at)?.status == .skipped)

        DoseActions.mark(.taken, medicationID: med.id, scheduledAt: at, amount: 2)
        DoseActions.undo(medicationID: med.id, scheduledAt: at)
        #expect(med.stockCount == 10)
        #expect(DataStore.log(medicationID: med.id, scheduledAt: at) == nil)
        DoseActions.delete(med)
    }

    @Test func noStockTrackingLeavesStockNil() {
        let med = makeMed(stock: nil)
        let at = Date.now.addingTimeInterval(-3600)
        DoseActions.mark(.taken, medicationID: med.id, scheduledAt: at, amount: 1)
        #expect(med.stockCount == nil)
        DoseActions.delete(med)
    }

    @Test func refillThresholdUsesDaysOfSupply() {
        let med = makeMed(stock: 9) // 2 per day → 4.5 days
        med.refillThresholdDays = 5
        #expect(med.daysOfSupply == 4.5)
        #expect(med.needsRefill)
        med.stockCount = 20
        #expect(!med.needsRefill)
        DoseActions.delete(med)
    }

    @Test func plannedDosesJoinLogsAndComputeAdherence() {
        let med = makeMed(stock: nil)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let doses = DosePlanner.doses(for: [med], on: yesterday, logs: [:])
        #expect(doses.count == 2)
        DoseActions.mark(.taken, medicationID: med.id, scheduledAt: doses[0].scheduledAt, amount: 1)
        let logs = DosePlanner.logIndex(DataStore.logs(from: Calendar.current.startOfDay(for: yesterday), to: .now))
        let stats = DosePlanner.stats(for: DosePlanner.doses(for: [med], on: yesterday, logs: logs))
        #expect(stats.scheduled == 2)
        #expect(stats.taken == 1)
        #expect(stats.missed == 1)
        #expect(stats.rate == 0.5)
        DoseActions.delete(med)
    }

    @Test func deletingMedicationRemovesItsLogs() {
        let med = makeMed(stock: nil)
        let id = med.id
        let at = Date.now.addingTimeInterval(-7200)
        DoseActions.mark(.taken, medicationID: id, scheduledAt: at, amount: 1)
        DoseActions.delete(med)
        #expect(DataStore.log(medicationID: id, scheduledAt: at) == nil)
    }
}
