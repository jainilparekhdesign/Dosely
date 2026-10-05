import Foundation

enum Fmt {
    static func time(minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date(timeIntervalSince1970: 0)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// 0.5 → "½", 1.5 → "1½", 2 → "2", 2.25 → "2.25"
    static func amount(_ value: Double) -> String {
        let whole = Int(value)
        let frac = value - Double(whole)
        let fracSymbol: String? = switch frac {
        case 0: ""
        case 0.25: "¼"
        case 0.5: "½"
        case 0.75: "¾"
        default: nil
        }
        guard let fracSymbol else { return value.formatted(.number.precision(.fractionLength(0...2))) }
        if whole == 0 && !fracSymbol.isEmpty { return fracSymbol }
        return "\(whole)\(fracSymbol)"
    }

    /// "1 tablet", "2 tablets", "½ tablet", "10 ml"
    static func dose(_ amount: Double, unit: String) -> String {
        let a = Self.amount(amount)
        let noPlural: Set<String> = ["ml", "mg", "g", "mcg", "iu", "units", "unit"]
        if amount <= 1 || noPlural.contains(unit.lowercased()) || unit.hasSuffix("s") {
            return "\(a) \(unit)"
        }
        return "\(a) \(unit)s"
    }

    /// Minutes after midnight <-> a Date today, for DatePicker bindings.
    static func date(fromMinutes minutes: Int, on day: Date = .now) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }
}
