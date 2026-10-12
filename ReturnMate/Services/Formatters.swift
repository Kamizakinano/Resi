import Foundation

enum Formatters {
    static let locale = Locale(identifier: "it_IT")

    static func money(_ value: Decimal?, currency: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency.uppercased()).locale(locale))
    }

    static func date(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    static func dateTime(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func isoDay(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func parseISODay(_ s: String?, timeZone: TimeZone = .current) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    static func daysLabel(_ days: Int) -> String {
        switch days {
        case ..<(-1): return "Scaduto da \(-days) giorni"
        case -1: return "Scaduto ieri"
        case 0: return "Scade oggi"
        case 1: return "Scade domani"
        default: return "\(days) giorni rimasti"
        }
    }

    /// Converte una stringa tipo "1.234,56" o "1,234.56" o "12.99" in Decimal.
    static func parseDecimal(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty else { return nil }
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        if let c = lastComma, let d = lastDot {
            if c > d { // 1.234,56
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else { // 1,234.56
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if let c = lastComma {
            let decimals = s.distance(from: c, to: s.endIndex) - 1
            if decimals == 3 && s.filter({ $0 == "," }).count >= 1 && !s.hasPrefix("0,") {
                s = s.replacingOccurrences(of: ",", with: "") // 1,234
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        } else if let d = lastDot {
            let decimals = s.distance(from: d, to: s.endIndex) - 1
            if decimals == 3 && s.filter({ $0 == "." }).count >= 1 && !s.hasPrefix("0.") {
                s = s.replacingOccurrences(of: ".", with: "") // 1.234
            }
        }
        guard s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func decimalString(_ d: Decimal?) -> String {
        guard let d else { return "" }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: d as NSDecimalNumber) ?? ""
    }
}
