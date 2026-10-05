import UIKit

/// Builds a printable adherence report (US Letter) for doctor visits.
@MainActor
enum ReportGenerator {
    struct Row {
        let med: Medication
        let stats: AdherenceStats
    }

    struct Event {
        let date: Date
        let med: Medication
        let status: DisplayStatus
    }

    static func makePDF(profileName: String, meds: [Medication], days: Int, now: Date = .now) -> URL? {
        let cal = Calendar.current
        let end = now
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now)) ?? now
        let logs = DosePlanner.logIndex(DataStore.logs(from: start, to: cal.date(byAdding: .day, value: 1, to: end) ?? end))
        let timed = meds.filter { $0.schedule.isTimed }
        let rows = timed.map { Row(med: $0, stats: DosePlanner.stats(for: [$0], from: start, to: end, logs: logs, now: now)) }
            .filter { $0.stats.scheduled > 0 || $0.med.isActive }
        let total = rows.reduce(AdherenceStats()) { $0 + $1.stats }

        var events: [Event] = []
        var day = start
        while day <= end {
            for dose in DosePlanner.doses(for: timed, on: day, logs: logs) {
                let s = dose.status(now: now)
                if s == .missed || s == .skipped { events.append(Event(date: dose.scheduledAt, med: dose.medication, status: s)) }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        events.sort { $0.date > $1.date }

        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let width = page.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: {
            let f = UIGraphicsPDFRendererFormat()
            f.documentInfo = [kCGPDFContextTitle as String: "Medication adherence report", kCGPDFContextCreator as String: "Dosely"]
            return f
        }())

        let data = renderer.pdfData { ctx in
            var y: CGFloat = 0
            func newPage() {
                ctx.beginPage()
                y = margin
            }
            func ensure(_ h: CGFloat) {
                if y + h > page.height - margin - 30 { footer(); newPage() }
            }
            func footer() {
                draw("Dosely does not provide medical advice. Data is self-reported by the patient.", at: CGPoint(x: margin, y: page.height - margin + 8),
                     width: width, font: .systemFont(ofSize: 8), color: .darkGray)
            }
            @discardableResult
            func text(_ s: String, font: UIFont, color: UIColor = .black, x: CGFloat = margin, w: CGFloat? = nil) -> CGFloat {
                let h = draw(s, at: CGPoint(x: x, y: y), width: w ?? width, font: font, color: color)
                return h
            }

            newPage()
            y += text("Medication Adherence Report", font: .systemFont(ofSize: 22, weight: .bold)) + 4
            let range = "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
            y += text("\(profileName) · \(range) (\(days) days)", font: .systemFont(ofSize: 12), color: .darkGray) + 2
            y += text("Generated \(now.formatted(date: .long, time: .shortened))", font: .systemFont(ofSize: 10), color: .darkGray) + 18

            // Summary
            let boxH: CGFloat = 64
            let boxW = (width - 24) / 4
            let summary: [(String, String)] = [
                ("Adherence", Fmt.percent(total.rate)), ("Taken", "\(total.taken)"),
                ("Missed", "\(total.missed)"), ("Skipped", "\(total.skipped)"),
            ]
            for (i, item) in summary.enumerated() {
                let rect = CGRect(x: margin + CGFloat(i) * (boxW + 8), y: y, width: boxW, height: boxH)
                UIColor(white: 0.95, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
                draw(item.0, at: CGPoint(x: rect.minX + 10, y: rect.minY + 10), width: boxW - 20, font: .systemFont(ofSize: 9, weight: .medium), color: .darkGray)
                draw(item.1, at: CGPoint(x: rect.minX + 10, y: rect.minY + 26), width: boxW - 20, font: .systemFont(ofSize: 20, weight: .bold))
            }
            y += boxH + 24

            // Medicines table
            y += text("Medicines", font: .systemFont(ofSize: 14, weight: .semibold)) + 8
            let cols: [CGFloat] = [0, 0.38, 0.72, 0.86]
            func header(_ titles: [String]) {
                for (i, t) in titles.enumerated() {
                    draw(t, at: CGPoint(x: margin + width * cols[i], y: y), width: width * 0.3, font: .systemFont(ofSize: 9, weight: .semibold), color: .darkGray)
                }
                y += 16
                UIColor.lightGray.setFill()
                UIRectFill(CGRect(x: margin, y: y - 3, width: width, height: 0.5))
            }
            header(["Medicine", "Schedule", "Taken / due", "Adherence"])
            for row in rows {
                ensure(36)
                let med = row.med
                UIColor(hexString: med.colorHex).setFill()
                UIBezierPath(ovalIn: CGRect(x: margin, y: y + 3, width: 8, height: 8)).fill()
                UIColor.lightGray.setStroke()
                UIBezierPath(ovalIn: CGRect(x: margin, y: y + 3, width: 8, height: 8)).stroke()
                let nameH = draw(med.displayName + (med.genericName.isEmpty ? "" : "\n\(med.genericName)"), at: CGPoint(x: margin + 14, y: y),
                                 width: width * cols[1] - 18, font: .systemFont(ofSize: 10, weight: .medium))
                let sched = "\(Fmt.dose(med.schedule.times.first?.amount ?? 1, unit: med.unit)) · \(med.schedule.frequencyText(med.mealTimes))\n\(med.schedule.timesText(med.mealTimes))"
                let schedH = draw(sched, at: CGPoint(x: margin + width * cols[1], y: y), width: width * (cols[2] - cols[1]) - 6, font: .systemFont(ofSize: 9), color: .darkGray)
                draw("\(row.stats.taken) / \(row.stats.scheduled)", at: CGPoint(x: margin + width * cols[2], y: y), width: 70, font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular))
                draw(Fmt.percent(row.stats.rate), at: CGPoint(x: margin + width * cols[3], y: y), width: 60, font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold))
                y += max(nameH, schedH) + 10
            }
            if rows.isEmpty { y += text("No scheduled medicines in this period.", font: .systemFont(ofSize: 10), color: .darkGray) + 8 }

            // Missed & skipped
            y += 16
            ensure(60)
            y += text("Missed and skipped doses", font: .systemFont(ofSize: 14, weight: .semibold)) + 8
            if events.isEmpty {
                y += text("None — every due dose was taken.", font: .systemFont(ofSize: 10), color: .darkGray)
            } else {
                for event in events.prefix(120) {
                    ensure(16)
                    let line = "\(event.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \(Fmt.time(event.date))"
                    draw(line, at: CGPoint(x: margin, y: y), width: 140, font: .monospacedDigitSystemFont(ofSize: 9, weight: .regular))
                    draw(event.med.displayName, at: CGPoint(x: margin + 150, y: y), width: 240, font: .systemFont(ofSize: 9))
                    draw(event.status.label, at: CGPoint(x: margin + 400, y: y), width: 80, font: .systemFont(ofSize: 9, weight: .semibold),
                         color: event.status == .missed ? UIColor(hexString: "#E0533D") : .darkGray)
                    y += 14
                }
                if events.count > 120 { y += text("…and \(events.count - 120) more", font: .systemFont(ofSize: 9), color: .darkGray) }
            }
            footer()
        }

        let safeName = profileName.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dosely-Report-\(safeName)-\(now.formatted(.iso8601.year().month().day())).pdf")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    @discardableResult
    nonisolated private static func draw(_ string: String, at point: CGPoint, width: CGFloat, font: UIFont, color: UIColor = .black) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let s = NSAttributedString(string: string, attributes: attrs)
        let bounds = s.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        s.draw(with: CGRect(origin: point, size: CGSize(width: width, height: ceil(bounds.height))), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(bounds.height)
    }
}

extension UIColor {
    convenience init(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0xFFFFFF
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
