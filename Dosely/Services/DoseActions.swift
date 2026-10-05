import Foundation
import SwiftData

/// The single place where doses are logged, so the app and notification actions behave identically
/// (stock counts, refill alerts and reminder refresh all follow from here).
@MainActor
enum DoseActions {
    static func mark(_ status: DoseStatus, medicationID: UUID, scheduledAt: Date, amount: Double, at actual: Date = .now) {
        guard let med = DataStore.medication(id: medicationID) else { return }
        let existing = DataStore.log(medicationID: medicationID, scheduledAt: scheduledAt)
        let wasTaken = existing?.status == .taken

        if let existing {
            existing.status = status
            existing.actualAt = actual
            existing.amount = amount
        } else {
            DataStore.context.insert(DoseLog(medicationID: medicationID, scheduledAt: scheduledAt, status: status, actualAt: actual, amount: amount))
        }
        adjustStock(med, wasTaken: wasTaken, isTaken: status == .taken, amount: amount)
        DataStore.save()
        afterChange(med)
    }

    static func undo(medicationID: UUID, scheduledAt: Date) {
        guard let log = DataStore.log(medicationID: medicationID, scheduledAt: scheduledAt) else { return }
        let med = DataStore.medication(id: medicationID)
        if let med { adjustStock(med, wasTaken: log.status == .taken, isTaken: false, amount: log.amount) }
        DataStore.context.delete(log)
        DataStore.save()
        if let med { afterChange(med) }
    }

    static func logAsNeeded(_ med: Medication, amount: Double, at date: Date = .now) {
        DataStore.context.insert(DoseLog(medicationID: med.id, scheduledAt: date, status: .taken, actualAt: date, amount: amount, isAsNeeded: true))
        adjustStock(med, wasTaken: false, isTaken: true, amount: amount)
        DataStore.save()
        afterChange(med)
    }

    static func deleteAsNeeded(_ log: DoseLog) {
        if let med = DataStore.medication(id: log.medicationID) {
            adjustStock(med, wasTaken: true, isTaken: false, amount: log.amount)
        }
        DataStore.context.delete(log)
        DataStore.save()
    }

    static func delete(_ med: Medication) {
        let id = med.id
        try? DataStore.context.delete(model: DoseLog.self, where: #Predicate { $0.medicationID == id })
        DataStore.context.delete(med)
        DataStore.save()
        NotificationService.shared.requestReschedule()
    }

    private static func adjustStock(_ med: Medication, wasTaken: Bool, isTaken: Bool, amount: Double) {
        guard var stock = med.stockCount, wasTaken != isTaken else { return }
        stock += isTaken ? -amount : amount
        med.stockCount = max(stock, 0)
    }

    private static func afterChange(_ med: Medication) {
        if med.needsRefill {
            let alreadyToday = med.lastRefillAlert.map { Calendar.current.isDateInToday($0) } ?? false
            if !alreadyToday {
                med.lastRefillAlert = .now
                DataStore.save()
                NotificationService.shared.sendRefillAlert(for: med)
            }
        }
        NotificationService.shared.requestReschedule()
    }
}
