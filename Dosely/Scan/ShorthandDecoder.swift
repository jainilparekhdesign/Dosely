import Foundation

/// Decoded "how often" from prescription text.
struct DecodedFrequency: Equatable {
    struct Slot: Equatable {
        var anchor: MealAnchor
        var amount: Double?
    }

    var pattern: SchedulePattern
    var slots: [Slot] = []
    var intervalHours: Int?
    var dayInterval: Int?
    /// The text that matched, shown on the review screen.
    var matched: String
}

/// Decodes US (QD, BID, TID, QID, q8h, HS, PRN) and Indian (OD, BD, TDS, SOS, 1-0-1, 5/7) prescription shorthand.
enum ShorthandDecoder {

    // MARK: Frequency

    static func frequency(in text: String) -> DecodedFrequency? {
        let lower = text.lowercased()
        if let d = dosingPattern(in: lower) { return d }

        // Strip dots between letters so "b.d." / "t.d.s" / "q.8.h" read as "bd" / "tds" / "q8h".
        let t = lower.replacingOccurrences(of: #"(?<=[a-z0-9])\.(?=[a-z0-9])"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[a-z])\.(?=\s|$)"#, with: "", options: .regularExpression)

        if let m = t.firstMatch(of: #"\bq\s*(\d{1,2})\s*(?:h|hr|hrs|hourly|hours?)\b"#) ?? t.firstMatch(of: #"\bevery\s+(\d{1,2})\s*(?:h|hr|hrs|hours?)\b"#),
           let hours = Int(m.groups[0]), hours > 0 {
            if hours >= 24 { return DecodedFrequency(pattern: .daily, slots: [.init(anchor: .breakfast)], matched: m.full) }
            return DecodedFrequency(pattern: .everyXHours, intervalHours: hours, matched: m.full)
        }

        let rules: [(String, (String) -> DecodedFrequency)] = [
            (#"\b(sos|prn|as needed|when needed|when required|if needed|as required|if required|as directed when needed)\b"#,
             { DecodedFrequency(pattern: .asNeeded, matched: $0) }),
            (#"\b(qid|qds|four times|4 times|4x)\b"#,
             { DecodedFrequency(pattern: .daily, slots: [.init(anchor: .breakfast), .init(anchor: .lunch), .init(anchor: .dinner), .init(anchor: .bedtime)], matched: $0) }),
            (#"\b(tid|tds|three times|thrice|3 times|3x)\b"#,
             { DecodedFrequency(pattern: .daily, slots: [.init(anchor: .breakfast), .init(anchor: .lunch), .init(anchor: .dinner)], matched: $0) }),
            (#"\b(bid|bd|twice|2 times|2x)\b"#,
             { DecodedFrequency(pattern: .daily, slots: [.init(anchor: .breakfast), .init(anchor: .dinner)], matched: $0) }),
            (#"\b(every other day|alternate days?|alt days?|qod|eod|on alternate days)\b"#,
             { DecodedFrequency(pattern: .everyXDays, slots: [.init(anchor: .breakfast)], dayInterval: 2, matched: $0) }),
            (#"\b(once a week|once weekly|weekly|every week|1/week)\b"#,
             { DecodedFrequency(pattern: .weekdays, slots: [.init(anchor: .breakfast)], matched: $0) }),
            (#"\b(hs|qhs|at bedtime|bedtime|at night|night)\b"#,
             { DecodedFrequency(pattern: .daily, slots: [.init(anchor: .bedtime)], matched: $0) }),
            (#"\b(od|qd|once daily|once a day|daily|once|1 time|qam|in the morning|morning|every day)\b"#,
             { DecodedFrequency(pattern: .daily, slots: [.init(anchor: .breakfast)], matched: $0) }),
        ]
        for (pattern, make) in rules {
            if let m = t.firstMatch(of: pattern) { return make(m.full) }
        }
        return nil
    }

    /// "1-0-1", "½-0-½", "1-1-1-1", "0-0-1", "1+0+1"
    static func dosingPattern(in lower: String) -> DecodedFrequency? {
        let part = #"(\d(?:\.5)?|½|1/2)"#
        let sep = #"\s*[-–—+]\s*"#
        let pattern = #"(?<![\d/.-])"# + part + sep + part + sep + part + "(?:" + sep + part + ")?" + #"(?![\d/-])"#
        guard let m = lower.firstMatch(of: pattern) else { return nil }
        let values = m.groups.filter { !$0.isEmpty }.map(parseAmount)
        guard values.allSatisfy({ $0 != nil }), values.compactMap({ $0 }).contains(where: { $0 > 0 }),
              values.compactMap({ $0 }).allSatisfy({ $0 <= 4 }) else { return nil }
        let anchors: [MealAnchor] = values.count == 4 ? [.breakfast, .lunch, .dinner, .bedtime] : [.breakfast, .lunch, .dinner]
        let slots = zip(anchors, values).compactMap { anchor, v -> DecodedFrequency.Slot? in
            guard let v, v > 0 else { return nil }
            return .init(anchor: anchor, amount: v)
        }
        return DecodedFrequency(pattern: .daily, slots: slots, matched: m.full)
    }

    // MARK: Food timing

    static func foodTiming(in text: String) -> FoodTiming? {
        let t = text.lowercased().replacingOccurrences(of: ".", with: "")
        if t.firstMatch(of: #"\b(empty stomach|on an empty stomach|fasting)\b"#) != nil { return .emptyStomach }
        if t.firstMatch(of: #"\b(ac|before food|before meals?|before breakfast|before lunch|before dinner|before eating|b/f)\b"#) != nil { return .before }
        if t.firstMatch(of: #"\b(pc|after food|after meals?|after breakfast|after lunch|after dinner|after eating|a/f)\b"#) != nil { return .after }
        if t.firstMatch(of: #"\b(with food|with meals?|with milk|with breakfast|with dinner)\b"#) != nil { return .with }
        return nil
    }

    // MARK: Duration

    /// Number of days in the course, or nil if not stated / ongoing.
    static func durationDays(in text: String) -> Int? {
        let t = text.lowercased()
        if t.firstMatch(of: #"\b(continue|lifelong|long term|ongoing|to continue)\b"#) != nil { return nil }
        // Indian notation: 5/7 = 5 days, 2/52 = 2 weeks, 1/12 = 1 month
        if let m = t.firstMatch(of: #"(?<![\d/])(\d{1,2})\s*/\s*(7|52|12)(?![\d/])"#), let n = Int(m.groups[0]) {
            switch m.groups[1] {
            case "7": return n
            case "52": return n * 7
            default: return n * 30
            }
        }
        if let m = t.firstMatch(of: #"(?:x|×|for)?\s*(\d{1,3})\s*(days?|d|weeks?|wks?|w|months?|mths?)\b"#), let n = Int(m.groups[0]), n > 0 {
            let unit = m.groups[1]
            if unit.hasPrefix("w") { return n * 7 }
            if unit.hasPrefix("m") { return n * 30 }
            return n
        }
        if t.firstMatch(of: #"\bfor (a|one) week\b"#) != nil { return 7 }
        if t.firstMatch(of: #"\bfor (a|one) month\b"#) != nil { return 30 }
        return nil
    }

    // MARK: Strength & dose

    struct Strength: Equatable {
        var text: String
        var range: Range<String.Index>
    }

    static func strength(in text: String) -> Strength? {
        let pattern = #"(\d+(?:\.\d+)?(?:\s*/\s*\d+(?:\.\d+)?)?)\s*(mg|mcg|µg|ug|gm|g|iu|units?|%)(?:\s*/\s*(\d+(?:\.\d+)?)\s*(ml|g))?(?![a-z])"#
        guard let m = text.firstMatch(of: pattern, caseInsensitive: true) else { return nil }
        var unit = m.groups[1].lowercased()
        if unit == "gm" { unit = "g" }
        if unit == "ug" || unit == "µg" { unit = "mcg" }
        if unit == "iu" { unit = "IU" }
        let number = m.groups[0].replacingOccurrences(of: " ", with: "")
        var s = "\(number) \(unit)"
        if !m.groups[2].isEmpty { s += "/\(m.groups[2]) \(m.groups[3].lowercased())" }
        return Strength(text: s, range: m.range)
    }

    struct Dose: Equatable {
        var amount: Double
        var unit: String
    }

    static func dose(in text: String, excluding: Range<String.Index>? = nil) -> Dose? {
        let pattern = #"(\d+(?:\.\d+)?|½|1/2|one|two|three|half)\s*(tabs?|tablets?|caps?|capsules?|puffs?|drops?|ml|units?|sachets?|spoons?|tsp|tbsp|injections?|patch(?:es)?)\b"#
        for m in text.allMatches(of: pattern, caseInsensitive: true) {
            if let excluding, m.range.overlaps(excluding) { continue }
            guard let amount = parseAmount(m.groups[0].lowercased()) else { continue }
            let raw = m.groups[1].lowercased()
            let unit: String = switch raw {
            case _ where raw.hasPrefix("tab"): "tablet"
            case _ where raw.hasPrefix("cap"): "capsule"
            case _ where raw.hasPrefix("puff"): "puff"
            case _ where raw.hasPrefix("drop"): "drop"
            case _ where raw.hasPrefix("unit"): "unit"
            case _ where raw.hasPrefix("sachet"): "sachet"
            case _ where raw.hasPrefix("injection"): "injection"
            case _ where raw.hasPrefix("patch"): "patch"
            case "tsp", "spoon", "spoons": "tsp"
            default: raw
            }
            return Dose(amount: amount, unit: unit)
        }
        return nil
    }

    static func parseAmount(_ s: String) -> Double? {
        switch s {
        case "½", "1/2", "half": 0.5
        case "one": 1
        case "two": 2
        case "three": 3
        default: Double(s)
        }
    }

    // MARK: Form prefix

    /// "Tab", "Cap", "Syp", "Inj", "Gtt" … at the start of a line.
    static func formPrefix(in text: String) -> (type: MedType, range: Range<String.Index>)? {
        let pattern = #"^\s*(tabs?|tablets?|t\.|cap|caps|capsules?|c\.|syp|syr|syrup|susp|suspension|liq|inj|injection|eye drops?|ear drops?|nasal drops?|drops?|gtt|inh|inhaler|rotacaps?|respules?|oint|ointment|cream|gel|lotion|patch)\.?(?=\s|$)"#
        guard let m = text.firstMatch(of: pattern, caseInsensitive: true) else { return nil }
        let word = m.groups[0].lowercased()
        let type: MedType
        if word.hasPrefix("t") { type = .tablet }
        else if word.hasPrefix("c") && !word.hasPrefix("cream") { type = .capsule }
        else if ["syp", "syr", "syrup", "susp", "suspension", "liq"].contains(word) { type = .liquid }
        else if word.hasPrefix("inj") { type = .injection }
        else if word.contains("drop") || word == "gtt" { type = .drops }
        else if word.hasPrefix("inh") || word.hasPrefix("rotacap") || word.hasPrefix("respule") { type = .inhaler }
        else if word == "patch" { type = .patch }
        else { type = .cream }
        return (type, m.range)
    }

    static func type(forDoseUnit unit: String) -> MedType? {
        switch unit {
        case "tablet": .tablet
        case "capsule": .capsule
        case "ml", "tsp", "sachet": .liquid
        case "puff": .inhaler
        case "drop": .drops
        case "injection", "unit": .injection
        case "patch": .patch
        default: nil
        }
    }
}

// MARK: - Regex helpers

struct RegexMatch {
    let full: String
    let groups: [String]
    let range: Range<String.Index>
}

extension String {
    func firstMatch(of pattern: String, caseInsensitive: Bool = false) -> RegexMatch? {
        allMatches(of: pattern, caseInsensitive: caseInsensitive).first
    }

    func allMatches(of pattern: String, caseInsensitive: Bool = false) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return [] }
        let ns = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: ns).compactMap { result in
            guard let r = Range(result.range, in: self) else { return nil }
            let groups = (1..<max(result.numberOfRanges, 1)).map { i -> String in
                guard let gr = Range(result.range(at: i), in: self) else { return "" }
                return String(self[gr])
            }
            return RegexMatch(full: String(self[r]), groups: groups, range: r)
        }
    }
}
