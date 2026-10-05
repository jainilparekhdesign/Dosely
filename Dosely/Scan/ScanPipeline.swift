import UIKit

/// Image → OCR → (on-device AI or rules) → drug matching → drafts for the review screen.
enum ScanPipeline {
    struct Output {
        var parsed: ParsedPrescription
        var lines: [String]
        var usedAI: Bool
    }

    static func run(image: UIImage, useAI: Bool, verifyOnline: Bool) async throws -> Output {
        let lines = try await TextRecognizer.recognizeLines(in: image)
        var usedAI = false
        var parsed = PrescriptionParser.parse(lines: lines)
        if useAI, let ai = await AIExtractor.extract(lines: lines), !ai.medications.isEmpty {
            // Prefer the AI's row grouping when it finds at least as many medicines.
            if ai.medications.count >= parsed.medications.count {
                if ai.doctor.isEmpty { var copy = ai; copy.doctor = parsed.doctor; parsed = copy } else { parsed = ai }
                usedAI = true
            }
        }
        if verifyOnline {
            for i in parsed.medications.indices where parsed.medications[i].match == nil {
                if let rx = await RxNormClient.lookup(parsed.medications[i].name) {
                    var med = parsed.medications[i]
                    med.notes.removeAll { $0.hasPrefix("Name not found") }
                    med.match = rx
                    parsed.medications[i] = PrescriptionParser.finalize(med)
                    if rx.exact { parsed.medications[i].notes.append("Confirmed in RxNorm.") }
                }
            }
        }
        #if DEBUG
        let dump = (["usedAI=\(usedAI) doctor=\(parsed.doctor) date=\(String(describing: parsed.date))", "--- OCR ---"] + lines + ["--- MEDS ---"]
            + parsed.medications.map { "\($0.name) | \($0.genericName) | \($0.strength) | \($0.type?.rawValue ?? "-") | dose=\($0.doseAmount ?? -1) \($0.doseUnit ?? "") | freq=\(String(describing: $0.frequency?.pattern)) \($0.frequency?.slots.map(\.anchor.rawValue) ?? []) | food=\(String(describing: $0.food)) | days=\(String(describing: $0.durationDays)) | conf n=\($0.nameConfidence) s=\($0.strengthConfidence) f=\($0.frequencyConfidence) | notes=\($0.notes)" })
            .joined(separator: "\n")
        try? dump.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("last_scan.txt"), atomically: true, encoding: .utf8)
        #endif
        return Output(parsed: parsed, lines: lines, usedAI: usedAI)
    }
}
