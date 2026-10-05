import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// Local reminders. iOS keeps at most 64 pending local notifications per app, so we schedule a rolling
/// window (next few days, capped) and refill it on launch, on foreground, after every change and from
/// background refresh. Doses sharing a time are grouped into one actionable notification.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    enum Action {
        static let taken = "TAKEN"
        static let skip = "SKIP"
        static let snooze10 = "SNOOZE_10"
        static let snooze30 = "SNOOZE_30"
    }
    nonisolated static let doseCategory = "DOSE"
    nonisolated static let refillCategory = "REFILL"

    /// Leaves headroom under the 64-request system limit for snoozes and refill alerts.
    private let maxPendingRequests = 56
    private let horizonDays = 4
    private var pendingReschedule: Task<Void, Never>?

    /// Set when the user taps a reminder, so the app can jump to Today.
    var onOpenDose: (() -> Void)?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let taken = UNNotificationAction(identifier: Action.taken, title: "Taken", options: [], icon: .init(systemImageName: "checkmark.circle.fill"))
        let snooze10 = UNNotificationAction(identifier: Action.snooze10, title: "Snooze 10 min", options: [], icon: .init(systemImageName: "clock"))
        let snooze30 = UNNotificationAction(identifier: Action.snooze30, title: "Snooze 30 min", options: [], icon: .init(systemImageName: "clock.badge"))
        let skip = UNNotificationAction(identifier: Action.skip, title: "Skip", options: [.destructive], icon: .init(systemImageName: "xmark.circle"))
        let dose = UNNotificationCategory(identifier: Self.doseCategory, actions: [taken, snooze10, snooze30, skip], intentIdentifiers: [],
                                          hiddenPreviewsBodyPlaceholder: "Medicine reminder", options: [.customDismissAction])
        let refill = UNNotificationCategory(identifier: Self.refillCategory, actions: [], intentIdentifiers: [])
        center.setNotificationCategories([dose, refill])
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await rescheduleAll() }
        return granted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Debounced, so a burst of edits causes one reschedule.
    func requestReschedule() {
        pendingReschedule?.cancel()
        pendingReschedule = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await rescheduleAll()
        }
    }

    // MARK: Scheduling

    private struct SlotItem {
        let med: Medication
        let at: Date
        let amount: Double
    }

    private struct Slot {
        let key: String
        let date: Date
        let profile: Profile?
        var items: [SlotItem]
    }

    func rescheduleAll() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let now = Date()
        let followUp = Prefs.followUp
        let from = now.addingTimeInterval(-Double(followUp ?? 0) * 60 - 60)
        let to = Calendar.current.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let meds = ((try? DataStore.context.fetch(FetchDescriptor<Medication>())) ?? []).filter { $0.isActive && $0.schedule.isTimed }
        let logIndex = DosePlanner.logIndex(DataStore.logs(from: from.addingTimeInterval(-86400), to: to))
        let multipleProfiles = DataStore.profiles().count > 1

        var slots: [String: Slot] = [:]
        for med in meds {
            for occ in ScheduleEngine.occurrences(of: med.schedule, from: from, to: to, meals: med.mealTimes) {
                guard logIndex[DoseKey.make(med.id, occ.date)] == nil, occ.date >= med.createdAt.addingTimeInterval(-60) else { continue }
                let key = "\(med.profile?.id.uuidString ?? "none")|\(Int(occ.date.timeIntervalSince1970))"
                slots[key, default: Slot(key: key, date: occ.date, profile: med.profile, items: [])].items
                    .append(SlotItem(med: med, at: occ.date, amount: occ.amount))
            }
        }

        // Remove our previous dose/nudge requests, and snoozes whose doses were since logged.
        let pending = await center.pendingNotificationRequests()
        var toRemove = pending.map(\.identifier).filter { $0.hasPrefix("dose|") || $0.hasPrefix("nudge|") }
        for request in pending where request.identifier.hasPrefix("snooze|") {
            if Self.allLogged(request.content.userInfo, in: logIndex) { toRemove.append(request.identifier) }
        }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
        let delivered = await center.deliveredNotifications()
        let staleDelivered = delivered.filter { Self.allLogged($0.request.content.userInfo, in: logIndex) }.map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: staleDelivered)

        var budget = maxPendingRequests - pending.filter { $0.identifier.hasPrefix("snooze|") || $0.identifier.hasPrefix("refill|") }.count
        for slot in slots.values.sorted(by: { $0.date < $1.date }) {
            guard budget > 0 else { break }
            let items = slot.items.sorted { $0.med.name < $1.med.name }
            if slot.date > now {
                let content = makeContent(items: items, profile: slot.profile, multipleProfiles: multipleProfiles, isNudge: false)
                try? await center.add(UNNotificationRequest(identifier: "dose|\(slot.key)", content: content, trigger: Self.trigger(at: slot.date)))
                budget -= 1
            }
            if let followUp, budget > 0 {
                let nudgeDate = slot.date.addingTimeInterval(Double(followUp) * 60)
                if nudgeDate > now && !Prefs.isQuiet(nudgeDate) {
                    let content = makeContent(items: items, profile: slot.profile, multipleProfiles: multipleProfiles, isNudge: true)
                    try? await center.add(UNNotificationRequest(identifier: "nudge|\(slot.key)", content: content, trigger: Self.trigger(at: nudgeDate)))
                    budget -= 1
                }
            }
        }
        #if DEBUG
        let scheduled = await center.pendingNotificationRequests().map { r in
            "\(r.identifier) | \((r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate().map { Fmt.time($0) + " " + $0.formatted(.dateTime.day().month()) } ?? "-") | \(r.content.title) | \(r.content.body.replacingOccurrences(of: "\n", with: " / ")) | att=\(r.content.attachments.count) | \(r.content.interruptionLevel.rawValue)"
        }.sorted()
        try? (["status=\(status.rawValue) count=\(scheduled.count)"] + scheduled).joined(separator: "\n")
            .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("pending_notifications.txt"), atomically: true, encoding: .utf8)
        #endif
    }

    private static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private static func allLogged(_ userInfo: [AnyHashable: Any], in index: [String: DoseLog]) -> Bool {
        guard let items = userInfo["items"] as? [[String: Any]], !items.isEmpty else { return false }
        return items.allSatisfy { item in
            guard let id = (item["med"] as? String).flatMap(UUID.init), let at = item["at"] as? Double else { return false }
            return index[DoseKey.make(id, Date(timeIntervalSince1970: at))] != nil
        }
    }

    private func makeContent(items: [SlotItem], profile: Profile?, multipleProfiles: Bool, isNudge: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let who = (multipleProfiles && profile?.isPrimary == false) ? "\(profile?.name ?? ""): " : ""
        if items.count == 1, let item = items.first {
            content.title = who + (isNudge ? "Did you take \(item.med.displayName)?" : item.med.displayName)
            var body = "Take \(Fmt.dose(item.amount, unit: item.med.unit))"
            if item.med.schedule.foodTiming != .any { body += " · \(item.med.schedule.foodTiming.label.lowercased())" }
            if !item.med.instructions.isEmpty && item.med.instructions != item.med.schedule.foodTiming.label { body += "\n\(item.med.instructions)" }
            content.body = isNudge ? "Still due from \(Fmt.time(item.at)). " + body : body
        } else {
            content.title = who + (isNudge ? "Did you take your \(items.count) medicines?" : "\(items.count) medicines due")
            content.body = items.map { "• \($0.med.displayName) — \(Fmt.dose($0.amount, unit: $0.med.unit))" }.joined(separator: "\n")
        }
        content.subtitle = isNudge ? "Reminder" : Fmt.time(items.first?.at ?? .now)
        content.categoryIdentifier = Self.doseCategory
        content.threadIdentifier = profile?.id.uuidString ?? "dosely"
        content.sound = .default
        let critical = items.contains { $0.med.isCritical }
        content.interruptionLevel = critical ? .timeSensitive : .active
        content.relevanceScore = critical ? 1 : 0.7
        content.userInfo = [
            "kind": "dose",
            "items": items.map { ["med": $0.med.id.uuidString, "at": $0.at.timeIntervalSince1970, "amt": $0.amount] as [String: Any] },
        ]
        if let first = items.first, let attachment = PillIconRenderer.attachment(for: first.med) {
            content.attachments = [attachment]
        }
        return content
    }

    func sendRefillAlert(for med: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "Running low: \(med.displayName)"
        let days = Int((med.daysOfSupply ?? 0).rounded(.down))
        let left = Fmt.dose(med.stockCount ?? 0, unit: med.unit)
        content.body = days <= 0 ? "You're out. Refill soon so you don't miss a dose." : "\(left) left — about \(days) day\(days == 1 ? "" : "s") of supply. Time to refill."
        content.categoryIdentifier = Self.refillCategory
        content.sound = .default
        let request = UNNotificationRequest(identifier: "refill|\(med.id.uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let request = response.notification.request
        guard request.content.categoryIdentifier == Self.doseCategory else { return }
        let items = Self.decodeItems(request.content.userInfo)
        let slotKey = request.identifier.split(separator: "|").dropFirst().prefix(2).joined(separator: "|")

        switch action {
        case Action.snooze10, Action.snooze30:
            let minutes = action == Action.snooze10 ? 10 : 30
            guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { return }
            content.subtitle = "Snoozed \(minutes) min"
            let snooze = UNNotificationRequest(identifier: "snooze|\(slotKey)|\(Int(Date().timeIntervalSince1970))", content: content,
                                               trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false))
            try? await center.add(snooze)
            center.removePendingNotificationRequests(withIdentifiers: ["nudge|\(slotKey)"])
        case Action.taken, Action.skip:
            let status: DoseStatus = action == Action.taken ? .taken : .skipped
            await MainActor.run {
                for item in items { DoseActions.mark(status, medicationID: item.id, scheduledAt: item.at, amount: item.amount) }
            }
            center.removePendingNotificationRequests(withIdentifiers: ["nudge|\(slotKey)"])
        case UNNotificationDefaultActionIdentifier:
            await MainActor.run { NotificationService.shared.onOpenDose?() }
        default:
            break
        }
    }

    nonisolated private static func decodeItems(_ userInfo: [AnyHashable: Any]) -> [(id: UUID, at: Date, amount: Double)] {
        guard let items = userInfo["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = (item["med"] as? String).flatMap(UUID.init), let at = item["at"] as? Double else { return nil }
            return (id, Date(timeIntervalSince1970: at), item["amt"] as? Double ?? 1)
        }
    }
}

/// Renders a medication's icon to a PNG for notification attachments.
@MainActor
enum PillIconRenderer {
    static func attachment(for med: Medication) -> UNNotificationAttachment? {
        let view = PillIconView(type: med.type, shape: med.shape, colorHex: med.colorHex, secondaryHex: med.secondaryColorHex, size: 96)
            .padding(16)
            .background(Color(white: 0.96))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pill-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "icon", url: url, options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false])
        } catch {
            return nil
        }
    }
}
