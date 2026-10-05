import Foundation
import FoundationModels

/// Optional structuring step using Apple's on-device foundation model. Nothing leaves the device.
/// The model only restructures OCR text; shorthand is still decoded by `ShorthandDecoder`
/// so the meaning of "BD" or "1-0-1" never depends on the model.
@Generable
struct AIPrescription {
    @Guide(description: "Prescribing doctor's name without degrees, or empty string if not present")
    var doctorName: String
    @Guide(description: "Every medicine prescribed, in order. Do not include tests, advice or diagnoses.")
    var medicines: [AIMedicine]
}

@Generable
struct AIMedicine {
    @Guide(description: "Medicine or brand name exactly as written, without the form or strength, e.g. Augmentin")
    var name: String
    @Guide(description: "Form: tablet, capsule, syrup, injection, drops, inhaler, cream, patch, or empty")
    var form: String
    @Guide(description: "Strength with unit, e.g. 500 mg or 625 mg, or empty")
    var strength: String
    @Guide(description: "Amount per intake with unit, e.g. 1 tablet, 2 puffs, 10 ml, or empty")
    var dosePerIntake: String
    @Guide(description: "Frequency exactly as written, e.g. BD, TDS, 1-0-1, q8h, SOS, once daily")
    var frequency: String
    @Guide(description: "Food timing as written, e.g. after food, before food, or empty")
    var foodTiming: String
    @Guide(description: "Duration as written, e.g. 5 days, 1 week, 5/7, or empty")
    var duration: String
}

enum AIExtractor {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func extract(lines: [String], timeout: Duration = .seconds(25)) async -> ParsedPrescription? {
        guard isAvailable else { return nil }
        let text = lines.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You read OCR text from doctors' prescriptions (US and India) and list the medicines on them. \
            Copy abbreviations such as OD, BD, TDS, QID, HS, SOS, PRN, q8h and patterns like 1-0-1 exactly as written. \
            Never invent medicines or values that are not in the text.
            """)
        do {
            let result = try await withThrowingTaskGroup(of: AIPrescription?.self) { group in
                group.addTask {
                    let response = try await session.respond(to: "Prescription text:\n\(text)", generating: AIPrescription.self)
                    return response.content
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }
                let first = try await group.next() ?? nil
                group.cancelAll()
                return first
            }
            guard let result, !result.medicines.isEmpty else { return nil }
            return convert(result, lines: lines)
        } catch {
            return nil
        }
    }

    /// Re-run each AI row through the deterministic parser so decoding and confidence are consistent.
    static func convert(_ ai: AIPrescription, lines: [String]) -> ParsedPrescription {
        var parsed = ParsedPrescription(rawText: lines.joined(separator: "\n"))
        parsed.doctor = ai.doctorName.isEmpty ? (PrescriptionParser.doctorName(in: lines) ?? "") : "Dr. " + ai.doctorName.replacingOccurrences(of: #"^(?i)dr\.?\s*"#, with: "", options: .regularExpression)
        parsed.date = PrescriptionParser.firstDate(in: parsed.rawText)
        parsed.medications = ai.medicines.compactMap { m in
            let name = m.name.trimmingCharacters(in: .whitespaces)
            guard name.count >= 2 else { return nil }
            let duration = m.duration.trimmingCharacters(in: .whitespaces)
            let durationText = duration.isEmpty || duration.lowercased().hasPrefix("x") || duration.lowercased().hasPrefix("for") ? duration : "x \(duration)"
            let line = [m.form, name, m.strength, m.dosePerIntake, m.frequency, m.foodTiming, durationText]
                .filter { !$0.isEmpty }.joined(separator: " ")
            // Show the user the original OCR line, not our reconstruction.
            let original = lines.first { $0.localizedCaseInsensitiveContains(name) }
            var med = PrescriptionParser.parseMedicationLine(line) ?? ParsedMedication(name: DrugDatabase.titled(name.lowercased()), sourceLine: line)
            med.name = DrugDatabase.titled(name.lowercased())
            med.match = DrugDatabase.match(name)
            if med.type == nil { med.type = formType(m.form) }
            med.sourceLine = original.map(PrescriptionParser.stripListMarker) ?? line
            return PrescriptionParser.finalize(med)
        }
        return parsed
    }

    private static func formType(_ form: String) -> MedType? {
        let f = form.lowercased()
        if f.contains("tab") { return .tablet }
        if f.contains("cap") { return .capsule }
        if f.contains("syr") || f.contains("susp") || f.contains("liquid") { return .liquid }
        if f.contains("inj") { return .injection }
        if f.contains("drop") { return .drops }
        if f.contains("inhal") || f.contains("puff") { return .inhaler }
        if f.contains("cream") || f.contains("oint") || f.contains("gel") { return .cream }
        if f.contains("patch") { return .patch }
        return nil
    }
}
