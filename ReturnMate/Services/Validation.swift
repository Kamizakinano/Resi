import Foundation

struct ValidationIssue: Hashable, Identifiable {
    enum Severity { case error, warning }
    var field: String
    var message: String
    var severity: Severity
    var id: String { field + message }
}

enum PurchaseValidator {

    static let knownCurrencies: Set<String> = Set(Locale.commonISOCurrencyCodes)

    static func validate(_ p: Purchase, now: Date = Date()) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func err(_ f: String, _ m: String) { issues.append(.init(field: f, message: m, severity: .error)) }
        func warn(_ f: String, _ m: String) { issues.append(.init(field: f, message: m, severity: .warning)) }

        if p.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            err("productName", "Il nome del prodotto è obbligatorio.")
        }
        if p.store.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            err("store", "Il negozio è obbligatorio.")
        }
        if let price = p.price, price < 0 {
            err("price", "Il prezzo non può essere negativo.")
        }
        if p.quantity < 1 {
            err("quantity", "La quantità deve essere almeno 1.")
        }
        if !knownCurrencies.contains(p.currency.uppercased()) {
            err("currency", "Valuta non riconosciuta: \(p.currency).")
        }
        if let o = p.orderDate, let d = p.deliveryDate, d < Calendar.current.startOfDay(for: o) {
            err("deliveryDate", "La consegna non può precedere l'ordine.")
        }
        if let o = p.orderDate, o > now.addingTimeInterval(86_400) {
            warn("orderDate", "La data dell'ordine è nel futuro.")
        }
        for (field, value) in [("productURL", p.productURL), ("orderURL", p.orderURL)] where !value.isEmpty {
            if !isValidWebURL(value) { err(field, "Il link non è valido.") }
        }
        if p.price == nil { warn("price", "Prezzo non indicato.") }
        if p.orderDate == nil && p.deliveryDate == nil {
            warn("dates", "Senza data d'ordine o di consegna non è possibile calcolare la scadenza.")
        } else if p.deliveryDate == nil && p.channel == .online {
            warn("deliveryDate", "Data di consegna mancante: la scadenza sarà provvisoria.")
        }
        if let r = p.refund.receivedAmount, r < 0 { err("refund", "Il rimborso non può essere negativo.") }
        if let c = p.refund.returnCost, c < 0 { err("returnCost", "Il costo di reso non può essere negativo.") }
        return issues
    }

    static func hasErrors(_ p: Purchase) -> Bool {
        validate(p).contains { $0.severity == .error }
    }

    static func isValidWebURL(_ s: String) -> Bool {
        guard let url = URL(string: s.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, host.contains(".") else { return false }
        return true
    }

    /// Prova a normalizzare un link scritto senza schema ("amazon.it/..." -> "https://amazon.it/...").
    static func normalizedURL(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") { return t }
        return "https://" + t
    }
}
