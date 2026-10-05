import Foundation

enum Confidence: Int, Comparable {
    case low, medium, high
    static func < (l: Confidence, r: Confidence) -> Bool { l.rawValue < r.rawValue }
}

struct ParsedMedication: Equatable {
    var name: String
    var genericName = ""
    var strength = ""
    var type: MedType?
    var doseAmount: Double?
    var doseUnit: String?
    var frequency: DecodedFrequency?
    var food: FoodTiming?
    var durationDays: Int?
    var sourceLine: String
    var match: DrugMatch?

    var nameConfidence: Confidence = .low
    var strengthConfidence: Confidence = .medium
    var frequencyConfidence: Confidence = .low
    /// Human-readable notes for the review screen.
    var notes: [String] = []

    var needsReview: Bool { nameConfidence == .low || frequencyConfidence == .low || strengthConfidence == .low }
}

struct ParsedPrescription: Equatable {
    var doctor: String = ""
    var date: Date?
    var medications: [ParsedMedication] = []
    var rawText: String = ""
}

/// Rule-based prescription reader. Deterministic and offline; also used to normalise AI output.
enum PrescriptionParser {
    private static let headerWords = #"^(dr\.?|doctor|patient|name|age|sex|gender|date|phone|ph|mob|mobile|tel|address|reg|regn|registration|clinic|hospital|diagnosis|dx|c/o|complaints?|bp|pulse|wt|weight|ht|height|temp|spo2|follow ?up|review|next visit|signature|sign|advice|investigations?|mbbs|md|uhid|op|ip|ref|email|www|timings?)\b"#

    private static let stopTokens: Set<String> = [
        "po", "od", "bd", "bid", "tds", "tid", "qid", "qds", "qd", "hs", "sos", "prn", "x", "×", "for", "take", "sig",
        "once", "twice", "thrice", "daily", "every", "after", "before", "with", "at", "in", "the", "a", "and", "-", "–",
        "orally", "oral", "by", "mouth", "morning", "night", "evening", "food", "meals", "meal", "tab", "tabs", "tablet",
        "tablets", "cap", "caps", "capsule", "capsules", "ml", "mg", "days", "day", "weeks", "week", "stat", "sl", "iv", "im",
        "sc", "q4h", "q6h", "q8h", "q12h", "ac", "pc", "bf", "af", "empty", "stomach", "as", "needed", "when", "required", "if",
    ]

    static func parse(lines rawLines: [String]) -> ParsedPrescription {
        var result = ParsedPrescription(rawText: rawLines.joined(separator: "\n"))
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        result.doctor = doctorName(in: lines) ?? ""
        result.date = firstDate(in: result.rawText)

        var meds: [ParsedMedication] = []
        for line in lines {
            let stripped = stripListMarker(line)
            if stripped.isEmpty { continue }
            if stripped.lowercased().firstMatch(of: headerWords) != nil { continue }

            if let med = parseMedicationLine(stripped) {
                meds.append(med)
            } else if !meds.isEmpty, isContinuation(stripped) {
                merge(stripped, into: &meds[meds.count - 1])
            }
        }
        result.medications = meds.map(finalize)
        return result
    }

    /// Parse a single line that should describe one medicine. Returns nil if it doesn't look like one.
    static func parseMedicationLine(_ line: String) -> ParsedMedication? {
        var rest = line
        var type: MedType?
        if let prefix = ShorthandDecoder.formPrefix(in: rest) {
            type = prefix.type
            rest = String(rest[prefix.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        let strength = ShorthandDecoder.strength(in: rest)
        let dose = ShorthandDecoder.dose(in: rest, excluding: strength?.range)
        let frequency = ShorthandDecoder.frequency(in: rest)
        let name = nameCandidate(in: rest)
        guard !name.isEmpty else { return nil }
        let match = DrugDatabase.match(name)

        // Needs some medicine signal beyond a bare word.
        let looksLikeMed = type != nil || strength != nil || match != nil || (frequency != nil && dose != nil)
        guard looksLikeMed else { return nil }

        var med = ParsedMedication(name: DrugDatabase.titled(name.lowercased()), sourceLine: line)
        med.type = type ?? dose.flatMap { ShorthandDecoder.type(forDoseUnit: $0.unit) }
        med.doseAmount = dose?.amount
        med.doseUnit = dose?.unit
        med.frequency = frequency
        med.food = ShorthandDecoder.foodTiming(in: rest)
        med.durationDays = ShorthandDecoder.durationDays(in: rest)
        med.match = match

        if let strength {
            med.strength = strength.text
            med.strengthConfidence = .high
        } else if let bare = rest.firstMatch(of: #"^\s*[A-Za-z][A-Za-z\-]*(?:\s+[A-Za-z][A-Za-z\-]*){0,2}\s+(\d{2,4})(?![\d/\-])(?!\s*(?:ml|tabs?|tablets?|caps?|capsules?|puffs?|drops?|units?|sachets?|tsp)\b)"#, caseInsensitive: true),
                  let n = Int(bare.groups[0]), n >= 5 {
            // "Dolo 650" — strength without a unit. Assume mg but ask the user to check.
            med.strength = "\(n) mg"
            med.strengthConfidence = .low
            med.notes.append("Strength had no unit — we assumed mg.")
        }
        return med
    }

    /// Lines like "1-0-1 x 5 days after food" that belong to the medicine above.
    static func isContinuation(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("sig") || lower.hasPrefix("take") || lower.hasPrefix("→") { return true }
        return ShorthandDecoder.frequency(in: line) != nil
            || ShorthandDecoder.durationDays(in: line) != nil
            || ShorthandDecoder.foodTiming(in: line) != nil
    }

    static func merge(_ line: String, into med: inout ParsedMedication) {
        if med.frequency == nil { med.frequency = ShorthandDecoder.frequency(in: line) }
        if med.food == nil { med.food = ShorthandDecoder.foodTiming(in: line) }
        if med.durationDays == nil { med.durationDays = ShorthandDecoder.durationDays(in: line) }
        if med.doseAmount == nil, let d = ShorthandDecoder.dose(in: line) {
            med.doseAmount = d.amount
            med.doseUnit = d.unit
            if med.type == nil { med.type = ShorthandDecoder.type(forDoseUnit: d.unit) }
        }
        med.sourceLine += "\n" + line
    }

    static func finalize(_ input: ParsedMedication) -> ParsedMedication {
        var med = input
        if let match = med.match {
            if match.exact {
                med.nameConfidence = .high
            } else {
                med.nameConfidence = .medium
                if match.name.lowercased() != med.name.lowercased() {
                    med.notes.append("Read as “\(med.name)” — corrected to \(match.name).")
                }
            }
            med.name = match.name
            if match.generic.lowercased() != match.name.lowercased() { med.genericName = match.generic }
        } else {
            med.nameConfidence = .low
            med.notes.append("Name not found in our medicine list — please check the spelling.")
        }

        if med.frequency != nil {
            med.frequencyConfidence = .high
        } else {
            med.frequencyConfidence = .low
            med.notes.append("Couldn't read how often to take it — set to once a day.")
        }
        if med.type == nil { med.type = .tablet }
        var seen = Set<String>()
        med.notes = med.notes.filter { seen.insert($0).inserted }
        return med
    }

    /// Words before the first number / dosing token, e.g. "Augmentin 625 mg 1-0-1" → "Augmentin".
    static func nameCandidate(in text: String) -> String {
        var words: [String] = []
        let tokens = text.replacingOccurrences(of: #"[,;:()\[\]]"#, with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        for token in tokens {
            let lower = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if stopTokens.contains(lower) { break }
            if lower.first?.isNumber == true { break }
            if lower.contains(where: \.isNumber) {
                // Allow "D3", "B12", "Taxim-O" style suffixes; stop at "500mg", "1-0-1".
                if lower.firstMatch(of: #"^[a-z]{1,3}\d{1,2}$"#) != nil && !words.isEmpty { words.append(token); continue }
                break
            }
            if lower.firstMatch(of: #"^[a-z][a-z\-\+']*$"#) == nil { break }
            words.append(token.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            if words.count == 4 { break }
        }
        let name = words.joined(separator: " ")
        return name.count >= 3 ? name : ""
    }

    static func stripListMarker(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\s*(?:rx[:.]?\s*|[•\-\*]\s*|\(?\d{1,2}[.)]\s+)+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    static func doctorName(in lines: [String]) -> String? {
        for line in lines {
            if let m = line.firstMatch(of: #"\b(?:dr\.?|doctor)\s+([A-Z][A-Za-z.'\-]*(?:\s+[A-Z][A-Za-z.'\-]*){0,3})"#, caseInsensitive: false)
                ?? line.firstMatch(of: #"\b(?:DR\.?|Dr\.?)\s*([A-Z][A-Za-z.'\-]*(?:\s+[A-Z][A-Za-z.'\-]*){0,3})"#) {
                let name = m.groups[0]
                    .replacingOccurrences(of: #"\s+(MBBS|MD|MS|DNB|FRCS|BDS|DM|MRCP).*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if name.count >= 3 { return "Dr. " + name }
            }
        }
        return nil
    }

    /// Numeric dates are ambiguous (03/10/2026 is 3 Oct in India, 10 Mar in the US). A prescription is never
    /// written in the future, so pick the reading that is on or before today and closest to it.
    static func firstDate(in text: String, now: Date = .now) -> Date? {
        let cal = Calendar.current
        if let m = text.firstMatch(of: #"(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?!\d)"#),
           let a = Int(m.groups[0]), let b = Int(m.groups[1]), var y = Int(m.groups[2]) {
            if y < 100 { y += 2000 }
            let latest = cal.date(byAdding: .day, value: 1, to: now) ?? now
            let candidates = [(a, b), (b, a)].compactMap { day, month -> Date? in
                guard (1...12).contains(month), (1...31).contains(day) else { return nil }
                let comps = DateComponents(year: y, month: month, day: day)
                guard comps.isValidDate(in: cal), let date = cal.date(from: comps), date <= latest else { return nil }
                return date
            }
            if let best = candidates.max() { return best }
        }
        return detectedDate(in: text)
    }

    private static func detectedDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.date).first { abs($0.timeIntervalSinceNow) < 5 * 365 * 86400 }
    }
}
