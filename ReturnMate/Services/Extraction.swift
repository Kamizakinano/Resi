import Foundation

struct ExtractedItem: Hashable, Identifiable {
    var id = UUID()
    var name: String = ""
    var price: Decimal?
    var quantity: Int = 1
    var productURL: String = ""
}

/// Bozza prodotta dall'importazione: viene sempre mostrata all'utente per la conferma.
struct ExtractionDraft: Hashable {
    var store: String = ""
    var storeCountry: String = "IT"
    var channel: PurchaseChannel = .online
    var orderNumber: String = ""
    var orderDate: Date?
    var deliveryDate: Date?
    var currency: String = "EUR"
    var orderURL: String = ""
    var items: [ExtractedItem] = [ExtractedItem()]
    var warnings: [String] = []
    var source: InputSource = .manual
    var usedAI = false

    func makePurchases(receipt: Attachment?, productPhoto: Attachment?) -> [Purchase] {
        let group = UUID()
        return items.map { item in
            var p = Purchase(productName: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                             store: store.trimmingCharacters(in: .whitespacesAndNewlines))
            p.orderGroup = group
            p.storeCountry = storeCountry.uppercased()
            p.channel = channel
            p.price = item.price
            p.quantity = max(1, item.quantity)
            p.currency = currency.uppercased()
            p.orderDate = orderDate
            p.deliveryDate = deliveryDate
            p.orderNumber = orderNumber.trimmingCharacters(in: .whitespaces)
            p.orderURL = orderURL.isEmpty ? "" : PurchaseValidator.normalizedURL(orderURL)
            p.productURL = item.productURL.isEmpty ? "" : PurchaseValidator.normalizedURL(item.productURL)
            p.source = source
            if let receipt { p.attachments.append(receipt) }
            if let productPhoto {
                p.attachments.append(productPhoto)
                p.imageAttachmentID = productPhoto.id
            }
            p.refund.expectedAmount = p.totalPrice
            return p
        }
    }
}

/// Estrazione locale (senza AI) da testo: prezzi, date, numero d'ordine, negozio.
/// Non inventa dati: ciò che non riconosce resta vuoto e viene segnalato.
enum HeuristicParser {

    static let knownStores: [(name: String, keys: [String], country: String?)] = [
        ("Amazon", ["amazon"], nil), ("Zalando", ["zalando"], nil), ("IKEA", ["ikea"], nil),
        ("MediaWorld", ["mediaworld"], "IT"), ("MediaMarkt", ["mediamarkt"], nil), ("Unieuro", ["unieuro"], "IT"),
        ("Euronics", ["euronics"], nil), ("Shein", ["shein"], nil), ("H&M", ["h&m", "hm.com"], nil),
        ("Zara", ["zara"], nil), ("Apple", ["apple.com", "apple store"], nil), ("Decathlon", ["decathlon"], nil),
        ("eBay", ["ebay"], nil), ("Temu", ["temu"], nil), ("AliExpress", ["aliexpress"], nil),
        ("Nike", ["nike"], nil), ("Adidas", ["adidas"], nil), ("Leroy Merlin", ["leroy merlin", "leroymerlin"], nil),
        ("Sephora", ["sephora"], nil), ("Douglas", ["douglas"], nil), ("Uniqlo", ["uniqlo"], nil),
        ("Mango", ["mango.com"], nil), ("Asos", ["asos"], nil), ("Yoox", ["yoox"], nil), ("Feltrinelli", ["feltrinelli"], "IT"),
        ("Mondadori Store", ["mondadoristore"], "IT"), ("ePrice", ["eprice"], "IT"), ("Trony", ["trony"], "IT"),
        ("Bershka", ["bershka"], nil), ("Pull&Bear", ["pull&bear", "pullandbear"], nil), ("OVS", ["ovs.it"], "IT"),
    ]

    static let tldCountry: [String: String] = [
        "it": "IT", "de": "DE", "fr": "FR", "es": "ES", "nl": "NL", "be": "BE", "at": "AT", "pt": "PT",
        "ie": "IE", "pl": "PL", "se": "SE", "dk": "DK", "fi": "FI", "uk": "GB", "ch": "CH",
    ]

    static let italianMonths: [String: Int] = [
        "gennaio": 1, "gen": 1, "febbraio": 2, "feb": 2, "marzo": 3, "mar": 3, "aprile": 4, "apr": 4,
        "maggio": 5, "mag": 5, "giugno": 6, "giu": 6, "luglio": 7, "lug": 7, "agosto": 8, "ago": 8,
        "settembre": 9, "set": 9, "sett": 9, "ottobre": 10, "ott": 10, "novembre": 11, "nov": 11, "dicembre": 12, "dic": 12,
        "january": 1, "jan": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "jun": 6,
        "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10,
        "november": 11, "december": 12, "dec": 12,
    ]

    struct FoundDate: Equatable {
        var date: Date
        var ambiguous: Bool
        var line: String
    }

    static func parse(_ text: String, source: InputSource, timeZone: TimeZone = .current, defaultCountry: String = "IT") -> ExtractionDraft {
        var draft = ExtractionDraft()
        draft.source = source
        draft.storeCountry = defaultCountry
        let lower = text.lowercased()
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Negozio e paese
        if let s = knownStores.first(where: { s in s.keys.contains { lower.contains($0) } }) {
            draft.store = s.name
            if let c = s.country { draft.storeCountry = c }
        }
        if let host = firstDomain(in: text) {
            if draft.store.isEmpty {
                let parts = host.split(separator: ".")
                if parts.count >= 2 { draft.store = String(parts[parts.count - 2]).capitalized }
            }
            if let tld = host.split(separator: ".").last, let c = tldCountry[String(tld)] { draft.storeCountry = c }
        }
        if let url = firstURL(in: text) { draft.orderURL = url }

        // Valuta
        if text.contains("£") || lower.contains("gbp") { draft.currency = "GBP" }
        else if text.contains("$") || lower.contains("usd") { draft.currency = "USD" }
        else if lower.contains("chf") { draft.currency = "CHF" }
        else { draft.currency = "EUR" }

        // Numero d'ordine
        draft.orderNumber = orderNumber(in: text) ?? ""

        // Date
        let dates = findDates(in: lines, timeZone: timeZone)
        for d in dates {
            let l = d.line.lowercased()
            if ["consegn", "deliver", "arriv", "ricevut", "recapitat"].contains(where: { l.contains($0) }) {
                if draft.deliveryDate == nil { draft.deliveryDate = d.date }
            } else if ["ordin", "order", "acquist", "effettuat", "data"].contains(where: { l.contains($0) }) {
                if draft.orderDate == nil { draft.orderDate = d.date }
            }
            if d.ambiguous {
                draft.warnings.append("Data ambigua \"\(d.line)\": interpretata come giorno/mese. Controllala.")
            }
        }
        if draft.orderDate == nil, draft.deliveryDate == nil, let first = dates.first {
            draft.orderDate = first.date
            draft.warnings.append("Non è chiaro se la data trovata sia dell'ordine o della consegna: impostata come data dell'ordine.")
        }

        // Prezzi
        let prices = findPrices(in: lines)
        if let total = prices.first(where: { p in ["totale", "total", "importo", "addebit"].contains(where: { p.line.lowercased().contains($0) }) }) {
            draft.items[0].price = total.value
            if prices.count > 1 { draft.warnings.append("Prezzo preso dal totale dell'ordine: se l'ordine contiene più prodotti, separali.") }
        } else if let only = prices.first {
            draft.items[0].price = only.value
            if Set(prices.map(\.value)).count > 1 { draft.warnings.append("Trovati più importi: controlla il prezzo.") }
        }

        // Nome prodotto: non viene indovinato.
        draft.warnings.append("Nome del prodotto non riconosciuto automaticamente: inseriscilo.")
        if draft.store.isEmpty { draft.warnings.append("Negozio non riconosciuto: inseriscilo.") }
        if draft.items[0].price == nil { draft.warnings.append("Prezzo non trovato.") }
        if draft.orderDate == nil && draft.deliveryDate == nil { draft.warnings.append("Nessuna data trovata.") }
        return draft
    }

    // MARK: - Componenti

    static func regex(_ pattern: String) -> NSRegularExpression {
        // I pattern sono costanti del codice: un errore qui è un bug di programmazione.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    static func matches(_ pattern: String, in s: String) -> [[String]] {
        let ns = s as NSString
        return regex(pattern).matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func firstURL(in text: String) -> String? {
        matches(#"https?://[^\s<>"']+"#, in: text).first?.first
    }

    static func firstDomain(in text: String) -> String? {
        if let url = firstURL(in: text), let host = URL(string: url)?.host {
            return host.lowercased().replacingOccurrences(of: "www.", with: "")
        }
        if let email = matches(#"[A-Z0-9._%+-]+@([A-Z0-9.-]+\.[A-Z]{2,})"#, in: text).first {
            let host = email[1].lowercased()
            let parts = host.split(separator: ".")
            // Gestisce domini come "mail.zalando.it"
            return parts.suffix(2).joined(separator: ".")
        }
        return nil
    }

    static func orderNumber(in text: String) -> String? {
        if let amazon = matches(#"\b(\d{3}-\d{7}-\d{7})\b"#, in: text).first { return amazon[1] }
        let pattern = #"(?:numero d['’]ordine|n(?:umero|r|\.)?\s*ordine|ordine\s*(?:n\.?|nr\.?|numero|#)|order\s*(?:number|no\.?|#|id)|order)\s*[:#°]?\s*([A-Z0-9][A-Z0-9\-_/]{3,})"#
        for m in matches(pattern, in: text) {
            let candidate = m[1]
            if candidate.contains(where: \.isNumber) { return candidate }
        }
        return nil
    }

    static func findDates(in lines: [String], timeZone: TimeZone) -> [FoundDate] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            var year = y
            if year < 100 { year += 2000 }
            guard (1...12).contains(m), (1...31).contains(d), (2000...2100).contains(year) else { return nil }
            let comps = DateComponents(year: year, month: m, day: d)
            guard let date = cal.date(from: comps), cal.component(.day, from: date) == d else { return nil }
            return date
        }
        var result: [FoundDate] = []
        for line in lines {
            for m in matches(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#, in: line) {
                if let d = make(Int(m[1])!, Int(m[2])!, Int(m[3])!) { result.append(.init(date: d, ambiguous: false, line: line)) }
            }
            for m in matches(#"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b"#, in: line) {
                let a = Int(m[1])!, b = Int(m[2])!, y = Int(m[3])!
                if let d = make(y, b, a) {
                    result.append(.init(date: d, ambiguous: a <= 12 && b <= 12 && a != b && !line.lowercased().contains("gg/mm"), line: line))
                } else if let d = make(y, a, b) {
                    // Formato mese/giorno (es. 10/25/2026): non ambiguo perché il giorno > 12.
                    result.append(.init(date: d, ambiguous: false, line: line))
                }
            }
            for m in matches(#"\b(\d{1,2})\s+([A-Za-zàèé]{3,10})\.?\s+(\d{4})\b"#, in: line) {
                if let month = italianMonths[m[2].lowercased()], let d = make(Int(m[3])!, month, Int(m[1])!) {
                    result.append(.init(date: d, ambiguous: false, line: line))
                }
            }
            for m in matches(#"\b([A-Za-z]{3,10})\.?\s+(\d{1,2}),?\s+(\d{4})\b"#, in: line) {
                if let month = italianMonths[m[1].lowercased()], let d = make(Int(m[3])!, month, Int(m[2])!) {
                    result.append(.init(date: d, ambiguous: false, line: line))
                }
            }
        }
        return result
    }

    struct FoundPrice: Equatable {
        var value: Decimal
        var line: String
    }

    static func findPrices(in lines: [String]) -> [FoundPrice] {
        var result: [FoundPrice] = []
        let number = #"(\d{1,3}(?:[.\s ]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
        let patterns = [
            #"(?:€|EUR|£|GBP|\$|USD|CHF)\s?"# + number,
            number + #"\s?(?:€|EUR|£|GBP|\$|USD|CHF)"#,
        ]
        for line in lines {
            for p in patterns {
                for m in matches(p, in: line) {
                    if let v = Formatters.parseDecimal(m[1]), v > 0 {
                        result.append(.init(value: v, line: line))
                    }
                }
            }
        }
        return result
    }
}
